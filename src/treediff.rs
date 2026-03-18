//! Main diff pipeline: parse with tree-sitter, diff with difftastic algorithm,
//! output ed-style diff for Neovim's diffexpr.

use std::path::Path;
use typed_arena::Arena;

use crate::diff::changes::ChangeMap;
use crate::diff::dijkstra;
use crate::diff::unchanged::mark_unchanged;
use crate::parse::syntax::{init_all_info, Syntax};
use crate::parse::tree_sitter_converter;

/// Load a tree-sitter language grammar from a .so file.
pub fn load_language(parser_path: &Path) -> Option<tree_sitter::Language> {
    let lib = unsafe { libloading::Library::new(parser_path).ok()? };
    // SAFETY: The parser .so exports a valid tree_sitter_language function.
    let lang_fn = unsafe {
        let func: libloading::Symbol<unsafe extern "C" fn() -> tree_sitter_language::LanguageFn> =
            lib.get(b"tree_sitter_language").ok()?;
        func()
    };
    // Keep the library alive (parsers are loaded once and persist)
    std::mem::forget(lib);
    let lang = tree_sitter::Language::new(lang_fn);
    Some(lang)
}

/// Parse source code with a tree-sitter language into difftastic Syntax nodes.
pub fn parse_to_syntax<'a>(
    src: &str,
    language: tree_sitter::Language,
    arena: &'a Arena<Syntax<'a>>,
) -> Vec<&'a Syntax<'a>> {
    let mut parser = tree_sitter::Parser::new();
    parser.set_language(&language).ok();
    let tree = match parser.parse(src, None) {
        Some(t) => t,
        None => return vec![],
    };
    tree_sitter_converter::to_syntax(&tree, src, arena)
}

/// Run the full difftastic pipeline on two source strings.
/// Returns a ChangeMap that can be queried for each syntax node.
pub fn diff_syntaxes<'a>(
    lhs_nodes: &[&'a Syntax<'a>],
    rhs_nodes: &[&'a Syntax<'a>],
) -> ChangeMap<'a> {
    let mut change_map = ChangeMap::default();

    if lhs_nodes.is_empty() && rhs_nodes.is_empty() {
        return change_map;
    }

    // Pre-process: mark unchanged subtrees to shrink the diff graph.
    let pairs = mark_unchanged(lhs_nodes, rhs_nodes, &mut change_map);

    // Run Dijkstra on each remaining pair.
    let graph_limit = 1_000_000;
    for (lhs_section, rhs_section) in &pairs {
        let lhs_root = lhs_section.first().copied();
        let rhs_root = rhs_section.first().copied();
        let _ = dijkstra::mark_syntax(lhs_root, rhs_root, &mut change_map, graph_limit);
    }

    change_map
}

/// Compute a structural diff and produce ed-style output for Neovim.
/// Falls back to line-level diff if tree-sitter parsing fails.
pub fn structural_diff(
    old_src: &str,
    new_src: &str,
    language: Option<tree_sitter::Language>,
) -> String {
    if let Some(lang) = language {
        let lhs_arena = Arena::new();
        let rhs_arena = Arena::new();

        let lhs_nodes = parse_to_syntax(old_src, lang.clone(), &lhs_arena);
        let rhs_nodes = parse_to_syntax(new_src, lang, &rhs_arena);

        if !lhs_nodes.is_empty() || !rhs_nodes.is_empty() {
            // Initialize all syntax node metadata (IDs, parents, siblings)
            init_all_info(&lhs_nodes, &rhs_nodes);

            let change_map = diff_syntaxes(&lhs_nodes, &rhs_nodes);

            // Convert to line-level pairings and produce ed-style output
            return change_map_to_ed_diff(old_src, new_src, &lhs_nodes, &rhs_nodes, &change_map);
        }
    }

    // Fallback: line-level diff using similar
    line_diff_ed_style(old_src, new_src)
}

/// Convert a ChangeMap into ed-style diff output by walking the syntax trees
/// and mapping novel nodes to line changes.
fn change_map_to_ed_diff<'a>(
    old_src: &str,
    new_src: &str,
    _lhs_nodes: &[&'a Syntax<'a>],
    _rhs_nodes: &[&'a Syntax<'a>],
    _change_map: &ChangeMap<'a>,
) -> String {
    // TODO: Walk the syntax trees, collect novel/unchanged line pairings,
    // and produce ed-style output. For now, fall back to line diff.
    line_diff_ed_style(old_src, new_src)
}

/// Line-level diff using the `similar` crate, producing ed-style output.
pub fn line_diff_ed_style(old_src: &str, new_src: &str) -> String {
    use similar::DiffOp;

    let diff = similar::TextDiff::from_lines(old_src, new_src);
    let mut result = String::new();

    for group in diff.grouped_ops(0) {
        for op in &group {
            match *op {
                DiffOp::Equal { .. } => {}
                DiffOp::Insert {
                    old_index,
                    new_index,
                    new_len,
                } => {
                    let new_start = new_index + 1;
                    let new_end = new_index + new_len;
                    if new_start == new_end {
                        result.push_str(&format!("{}a{}\n", old_index, new_start));
                    } else {
                        result.push_str(&format!("{}a{},{}\n", old_index, new_start, new_end));
                    }
                    for i in new_index..new_index + new_len {
                        let line = diff.new_slices()[i];
                        result.push_str(&format!("> {}", line));
                        if !line.ends_with('\n') {
                            result.push('\n');
                        }
                    }
                }
                DiffOp::Delete {
                    old_index,
                    old_len,
                    new_index,
                } => {
                    let old_start = old_index + 1;
                    let old_end = old_index + old_len;
                    if old_start == old_end {
                        result.push_str(&format!("{}d{}\n", old_start, new_index));
                    } else {
                        result.push_str(&format!("{},{}d{}\n", old_start, old_end, new_index));
                    }
                    for i in old_index..old_index + old_len {
                        let line = diff.old_slices()[i];
                        result.push_str(&format!("< {}", line));
                        if !line.ends_with('\n') {
                            result.push('\n');
                        }
                    }
                }
                DiffOp::Replace {
                    old_index,
                    old_len,
                    new_index,
                    new_len,
                } => {
                    let old_start = old_index + 1;
                    let old_end = old_index + old_len;
                    let new_start = new_index + 1;
                    let new_end = new_index + new_len;
                    if old_start == old_end && new_start == new_end {
                        result.push_str(&format!("{}c{}\n", old_start, new_start));
                    } else if old_start == old_end {
                        result.push_str(&format!("{}c{},{}\n", old_start, new_start, new_end));
                    } else if new_start == new_end {
                        result.push_str(&format!("{},{}c{}\n", old_start, old_end, new_start));
                    } else {
                        result.push_str(&format!(
                            "{},{}c{},{}\n",
                            old_start, old_end, new_start, new_end
                        ));
                    }
                    for i in old_index..old_index + old_len {
                        let line = diff.old_slices()[i];
                        result.push_str(&format!("< {}", line));
                        if !line.ends_with('\n') {
                            result.push('\n');
                        }
                    }
                    result.push_str("---\n");
                    for i in new_index..new_index + new_len {
                        let line = diff.new_slices()[i];
                        result.push_str(&format!("> {}", line));
                        if !line.ends_with('\n') {
                            result.push('\n');
                        }
                    }
                }
            }
        }
    }

    result
}
