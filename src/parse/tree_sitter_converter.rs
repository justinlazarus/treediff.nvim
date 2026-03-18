//! Convert tree-sitter parse trees into difftastic's Syntax type.
//!
//! This is a simplified version of difftastic's tree_sitter_parser.rs.
//! It treats nodes with children as List nodes (using first/last tokens
//! as delimiters when they look like punctuation) and leaf nodes as Atoms.

use line_numbers::{LinePositions, SingleLineSpan};
use typed_arena::Arena;

use crate::parse::syntax::{AtomKind, StringKind, Syntax};

/// Common delimiter pairs across languages.
const DELIMITER_PAIRS: &[(&str, &str)] = &[
    ("(", ")"),
    ("[", "]"),
    ("{", "}"),
    ("<", ">"),
];

/// Convert a tree-sitter tree into difftastic Syntax nodes.
pub fn to_syntax<'a>(
    tree: &tree_sitter::Tree,
    src: &str,
    arena: &'a Arena<Syntax<'a>>,
) -> Vec<&'a Syntax<'a>> {
    if src.trim().is_empty() {
        return vec![];
    }

    let nl_pos = LinePositions::from(src);
    let mut cursor = tree.walk();

    // The tree always has a single root; we want its children.
    if !cursor.goto_first_child() {
        return vec![];
    }

    let mut nodes = vec![];
    loop {
        if let Some(syntax) = node_to_syntax(arena, src, &nl_pos, &mut cursor) {
            nodes.push(syntax);
        }
        if !cursor.goto_next_sibling() {
            break;
        }
    }

    nodes
}

/// Recursively convert a tree-sitter node at the cursor position into Syntax.
fn node_to_syntax<'a>(
    arena: &'a Arena<Syntax<'a>>,
    src: &str,
    nl_pos: &LinePositions,
    cursor: &mut tree_sitter::TreeCursor,
) -> Option<&'a Syntax<'a>> {
    let node = cursor.node();

    // Skip zero-width nodes
    if node.start_byte() == node.end_byte() {
        return None;
    }

    let child_count = node.child_count();

    if child_count == 0 {
        // Leaf node → Atom
        let content = src[node.start_byte()..node.end_byte()].to_string();
        let position = lsp_positions(nl_pos, node.start_byte(), node.end_byte(), src);
        let kind = classify_atom(node, &content);

        Some(Syntax::new_atom(arena, position, content, kind))
    } else {
        // Internal node → try to find delimiters, make a List
        let (open_content, open_position, close_content, close_position, children) =
            build_list_parts(arena, src, nl_pos, cursor);

        Some(Syntax::new_list(
            arena,
            &open_content,
            open_position,
            children,
            &close_content,
            close_position,
        ))
    }
}

/// Build the parts needed for a Syntax::List from the current cursor node.
fn build_list_parts<'a>(
    arena: &'a Arena<Syntax<'a>>,
    src: &str,
    nl_pos: &LinePositions,
    cursor: &mut tree_sitter::TreeCursor,
) -> (String, Vec<SingleLineSpan>, String, Vec<SingleLineSpan>, Vec<&'a Syntax<'a>>) {
    let node = cursor.node();
    let child_count = node.child_count();

    // Check if first and last children are matching delimiters
    let first_child = node.child(0);
    let last_child = node.child(child_count as u32 - 1);

    let mut open_content = String::new();
    let mut open_position = vec![];
    let mut close_content = String::new();
    let mut close_position = vec![];
    let mut delim_first = false;
    let mut delim_last = false;

    if let (Some(first), Some(last)) = (first_child, last_child) {
        let first_text = &src[first.start_byte()..first.end_byte()];
        let last_text = &src[last.start_byte()..last.end_byte()];

        for (open, close) in DELIMITER_PAIRS {
            if first_text == *open && last_text == *close {
                open_content = open.to_string();
                open_position = lsp_positions(nl_pos, first.start_byte(), first.end_byte(), src);
                close_content = close.to_string();
                close_position = lsp_positions(nl_pos, last.start_byte(), last.end_byte(), src);
                delim_first = true;
                delim_last = true;
                break;
            }
        }
    }

    // Collect children (skip delimiters if we found them)
    let mut children = vec![];
    cursor.goto_first_child();
    let mut child_idx = 0;
    loop {
        let skip = (delim_first && child_idx == 0)
            || (delim_last && child_idx == child_count - 1);

        if !skip {
            if let Some(child_syntax) = node_to_syntax(arena, src, nl_pos, cursor) {
                children.push(child_syntax);
            }
        }
        child_idx += 1;
        if !cursor.goto_next_sibling() {
            break;
        }
    }
    cursor.goto_parent();

    (open_content, open_position, close_content, close_position, children)
}

/// Classify a leaf node as Comment, String, or Normal.
fn classify_atom(node: tree_sitter::Node, content: &str) -> AtomKind {
    let kind = node.kind();
    if kind.contains("comment") || content.starts_with("//") || content.starts_with("/*") {
        AtomKind::Comment
    } else if kind.contains("string") || kind == "string_literal"
        || kind == "template_string" || kind == "raw_string_literal"
        || (content.starts_with('"') && content.ends_with('"'))
        || (content.starts_with('\'') && content.ends_with('\''))
    {
        AtomKind::String(StringKind::StringLiteral)
    } else {
        AtomKind::Normal
    }
}

/// Convert byte offsets to SingleLineSpan positions.
fn lsp_positions(
    nl_pos: &LinePositions,
    start_byte: usize,
    end_byte: usize,
    _src: &str,
) -> Vec<SingleLineSpan> {
    nl_pos.from_region(start_byte, end_byte)
}
