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

/// Collect all line numbers that contain novel (changed) syntax nodes.
fn collect_novel_lines<'a>(
    nodes: &[&'a Syntax<'a>],
    change_map: &ChangeMap<'a>,
    novel_lines: &mut std::collections::BTreeSet<usize>,
) {
    use crate::diff::changes::ChangeKind;

    for node in nodes {
        let change = change_map.get(node);
        match change {
            Some(ChangeKind::Novel)
            | Some(ChangeKind::ReplacedComment(_, _))
            | Some(ChangeKind::ReplacedString(_, _)) => {
                // This node is changed — mark all its lines
                match node {
                    Syntax::Atom { position, .. } => {
                        for span in position {
                            novel_lines.insert(span.line.0 as usize);
                        }
                    }
                    Syntax::List {
                        open_position,
                        close_position,
                        children,
                        ..
                    } => {
                        for span in open_position {
                            novel_lines.insert(span.line.0 as usize);
                        }
                        for span in close_position {
                            novel_lines.insert(span.line.0 as usize);
                        }
                        // Mark all children's lines too
                        for child in children {
                            mark_all_lines(child, novel_lines);
                        }
                    }
                }
            }
            Some(ChangeKind::Unchanged(_)) => {
                // For List nodes, children might still differ
                if let Syntax::List { children, .. } = node {
                    collect_novel_lines(children, change_map, novel_lines);
                }
            }
            None => {
                // No change info — recurse into children
                if let Syntax::List { children, .. } = node {
                    collect_novel_lines(children, change_map, novel_lines);
                }
            }
        }
    }
}

/// Mark ALL lines covered by a syntax node and its descendants.
fn mark_all_lines(node: &Syntax, lines: &mut std::collections::BTreeSet<usize>) {
    match node {
        Syntax::Atom { position, .. } => {
            for span in position {
                lines.insert(span.line.0 as usize);
            }
        }
        Syntax::List {
            open_position,
            close_position,
            children,
            ..
        } => {
            for span in open_position {
                lines.insert(span.line.0 as usize);
            }
            for span in close_position {
                lines.insert(span.line.0 as usize);
            }
            for child in children {
                mark_all_lines(child, lines);
            }
        }
    }
}

/// Convert a ChangeMap into ed-style diff output by walking the syntax trees,
/// finding which lines have novel content, and producing diff commands.
fn change_map_to_ed_diff<'a>(
    old_src: &str,
    new_src: &str,
    lhs_nodes: &[&'a Syntax<'a>],
    rhs_nodes: &[&'a Syntax<'a>],
    change_map: &ChangeMap<'a>,
) -> String {
    let mut lhs_novel = std::collections::BTreeSet::new();
    let mut rhs_novel = std::collections::BTreeSet::new();

    collect_novel_lines(lhs_nodes, change_map, &mut lhs_novel);
    collect_novel_lines(rhs_nodes, change_map, &mut rhs_novel);

    // If no changes detected, return empty
    if lhs_novel.is_empty() && rhs_novel.is_empty() {
        return String::new();
    }

    let old_lines: Vec<&str> = old_src.lines().collect();
    let new_lines: Vec<&str> = new_src.lines().collect();

    // Build ed-style diff from the novel line sets.
    // Walk both files in parallel, matching unchanged lines and
    // grouping novel lines into add/delete/change commands.
    let mut result = String::new();
    let mut oi = 0usize; // position in old
    let mut ni = 0usize; // position in new

    while oi < old_lines.len() || ni < new_lines.len() {
        if oi < old_lines.len() && ni < new_lines.len()
            && !lhs_novel.contains(&oi) && !rhs_novel.contains(&ni)
        {
            // Both lines unchanged — advance
            oi += 1;
            ni += 1;
            continue;
        }

        // Collect consecutive novel lines on each side
        let old_start = oi;
        let new_start = ni;
        while oi < old_lines.len() && lhs_novel.contains(&oi) {
            oi += 1;
        }
        while ni < new_lines.len() && rhs_novel.contains(&ni) {
            ni += 1;
        }

        let del_count = oi - old_start;
        let add_count = ni - new_start;

        if del_count == 0 && add_count == 0 {
            // Neither side has novel lines but they didn't match above.
            // This can happen when lines are unchanged per tree diff
            // but shifted. Just advance both.
            oi += 1;
            ni += 1;
            continue;
        }

        if del_count > 0 && add_count > 0 {
            // Change
            let os = old_start + 1;
            let oe = oi;
            let ns = new_start + 1;
            let ne = ni;
            if os == oe && ns == ne {
                result.push_str(&format!("{}c{}\n", os, ns));
            } else if os == oe {
                result.push_str(&format!("{}c{},{}\n", os, ns, ne));
            } else if ns == ne {
                result.push_str(&format!("{},{}c{}\n", os, oe, ns));
            } else {
                result.push_str(&format!("{},{}c{},{}\n", os, oe, ns, ne));
            }
            for k in old_start..oi {
                result.push_str(&format!("< {}\n", old_lines[k]));
            }
            result.push_str("---\n");
            for k in new_start..ni {
                result.push_str(&format!("> {}\n", new_lines[k]));
            }
        } else if del_count > 0 {
            // Delete
            let os = old_start + 1;
            let oe = oi;
            if os == oe {
                result.push_str(&format!("{}d{}\n", os, new_start));
            } else {
                result.push_str(&format!("{},{}d{}\n", os, oe, new_start));
            }
            for k in old_start..oi {
                result.push_str(&format!("< {}\n", old_lines[k]));
            }
        } else {
            // Add
            let ns = new_start + 1;
            let ne = ni;
            if ns == ne {
                result.push_str(&format!("{}a{}\n", old_start, ns));
            } else {
                result.push_str(&format!("{}a{},{}\n", old_start, ns, ne));
            }
            for k in new_start..ni {
                result.push_str(&format!("> {}\n", new_lines[k]));
            }
        }
    }

    result
}

/// A token with its position and change kind, for Lua consumption.
#[derive(Debug, Clone)]
pub struct TokenInfo {
    pub line: usize,       // 0-indexed line number
    pub start_col: usize,  // 0-indexed byte offset within line
    pub end_col: usize,    // 0-indexed byte offset end
    pub kind: TokenChange, // novel, unchanged, etc.
}

#[derive(Debug, Clone, PartialEq)]
pub enum TokenChange {
    Novel,
    Unchanged,
}

/// Full structured diff result for Lua consumption.
#[derive(Debug)]
pub struct DiffResult {
    pub lhs_tokens: Vec<TokenInfo>,
    pub rhs_tokens: Vec<TokenInfo>,
}

/// Collect token-level change info from syntax nodes.
fn collect_tokens<'a>(
    nodes: &[&'a Syntax<'a>],
    change_map: &ChangeMap<'a>,
    tokens: &mut Vec<TokenInfo>,
) {
    use crate::diff::changes::ChangeKind;

    for node in nodes {
        let change = change_map.get(node);
        match change {
            Some(ChangeKind::Novel) => {
                add_node_tokens(node, TokenChange::Novel, tokens);
            }
            Some(ChangeKind::ReplacedComment(_, _))
            | Some(ChangeKind::ReplacedString(_, _)) => {
                add_node_tokens(node, TokenChange::Novel, tokens);
            }
            Some(ChangeKind::Unchanged(_)) => {
                match node {
                    Syntax::Atom { position, .. } => {
                        for span in position {
                            tokens.push(TokenInfo {
                                line: span.line.0 as usize,
                                start_col: span.start_col as usize,
                                end_col: span.end_col as usize,
                                kind: TokenChange::Unchanged,
                            });
                        }
                    }
                    Syntax::List { children, .. } => {
                        // Delimiters unchanged, but children may differ
                        collect_tokens(children, change_map, tokens);
                    }
                }
            }
            None => {
                if let Syntax::List { children, .. } = node {
                    collect_tokens(children, change_map, tokens);
                }
            }
        }
    }
}

/// Add all spans of a syntax node (and its descendants) as tokens.
fn add_node_tokens(node: &Syntax, kind: TokenChange, tokens: &mut Vec<TokenInfo>) {
    match node {
        Syntax::Atom { position, .. } => {
            for span in position {
                tokens.push(TokenInfo {
                    line: span.line.0 as usize,
                    start_col: span.start_col as usize,
                    end_col: span.end_col as usize,
                    kind: kind.clone(),
                });
            }
        }
        Syntax::List {
            open_position,
            close_position,
            children,
            ..
        } => {
            for span in open_position {
                tokens.push(TokenInfo {
                    line: span.line.0 as usize,
                    start_col: span.start_col as usize,
                    end_col: span.end_col as usize,
                    kind: kind.clone(),
                });
            }
            for child in children {
                add_node_tokens(child, kind.clone(), tokens);
            }
            for span in close_position {
                tokens.push(TokenInfo {
                    line: span.line.0 as usize,
                    start_col: span.start_col as usize,
                    end_col: span.end_col as usize,
                    kind: kind.clone(),
                });
            }
        }
    }
}

/// Compute a structural diff returning token-level change data.
/// This is the API that plz.nvim (or any plugin) calls.
pub fn diff_tokens(
    old_src: &str,
    new_src: &str,
    language: Option<tree_sitter::Language>,
) -> Option<DiffResult> {
    let lang = language?;
    let lhs_arena = Arena::new();
    let rhs_arena = Arena::new();

    let lhs_nodes = parse_to_syntax(old_src, lang.clone(), &lhs_arena);
    let rhs_nodes = parse_to_syntax(new_src, lang, &rhs_arena);

    if lhs_nodes.is_empty() && rhs_nodes.is_empty() {
        return None;
    }

    init_all_info(&lhs_nodes, &rhs_nodes);
    let change_map = diff_syntaxes(&lhs_nodes, &rhs_nodes);

    let mut lhs_tokens = Vec::new();
    let mut rhs_tokens = Vec::new();

    collect_tokens(&lhs_nodes, &change_map, &mut lhs_tokens);
    collect_tokens(&rhs_nodes, &change_map, &mut rhs_tokens);

    Some(DiffResult {
        lhs_tokens,
        rhs_tokens,
    })
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
