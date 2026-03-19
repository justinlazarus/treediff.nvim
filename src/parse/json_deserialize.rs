//! Deserialize JSON syntax trees from Lua into arena-allocated Syntax nodes.
//!
//! The JSON format matches what `lua/treediff/tree_walker.lua` produces:
//!
//! Atom: `{"atom": {"content": "fn", "kind": "normal", "pos": [{"line":0,"start_col":0,"end_col":2}]}}`
//! List: `{"list": {"open": "{", "open_pos": [...], "close": "}", "close_pos": [...], "children": [...]}}`

use line_numbers::SingleLineSpan;
use serde::Deserialize;
use typed_arena::Arena;

use crate::parse::syntax::{AtomKind, StringKind, Syntax};

#[derive(Deserialize, Debug)]
struct SpanJson {
    line: u32,
    start_col: u32,
    end_col: u32,
}

impl SpanJson {
    fn to_single_line_span(&self) -> SingleLineSpan {
        SingleLineSpan {
            line: self.line.into(),
            start_col: self.start_col,
            end_col: self.end_col,
        }
    }
}

#[derive(Deserialize, Debug)]
struct AtomJson {
    content: String,
    kind: String,
    pos: Vec<SpanJson>,
}

#[derive(Deserialize, Debug)]
struct ListJson {
    open: String,
    open_pos: Vec<SpanJson>,
    close: String,
    close_pos: Vec<SpanJson>,
    children: Vec<NodeJson>,
}

#[derive(Deserialize, Debug)]
#[serde(untagged)]
enum NodeJson {
    Atom { atom: AtomJson },
    List { list: ListJson },
}

fn parse_atom_kind(s: &str) -> AtomKind {
    match s {
        "comment" => AtomKind::Comment,
        "string" => AtomKind::String(StringKind::StringLiteral),
        "text" => AtomKind::String(StringKind::Text),
        "error" => AtomKind::TreeSitterError,
        "type" => AtomKind::Type,
        "keyword" => AtomKind::Keyword,
        _ => AtomKind::Normal,
    }
}

fn spans_from_json(spans: &[SpanJson]) -> Vec<SingleLineSpan> {
    spans.iter().map(|s| s.to_single_line_span()).collect()
}

fn node_to_syntax<'a>(node: &NodeJson, arena: &'a Arena<Syntax<'a>>) -> Option<&'a Syntax<'a>> {
    match node {
        NodeJson::Atom { atom } => {
            let position = spans_from_json(&atom.pos);
            let kind = parse_atom_kind(&atom.kind);
            Some(Syntax::new_atom(
                arena,
                position,
                atom.content.clone(),
                kind,
            ))
        }
        NodeJson::List { list } => {
            let open_position = spans_from_json(&list.open_pos);
            let close_position = spans_from_json(&list.close_pos);
            let children: Vec<&'a Syntax<'a>> = list
                .children
                .iter()
                .filter_map(|child| node_to_syntax(child, arena))
                .collect();
            Some(Syntax::new_list(
                arena,
                &list.open,
                open_position,
                children,
                &list.close,
                close_position,
            ))
        }
    }
}

/// Deserialize a JSON array of syntax nodes into arena-allocated Syntax nodes.
///
/// Returns an empty Vec on parse failure or empty input.
pub fn json_to_syntax<'a>(json: &str, arena: &'a Arena<Syntax<'a>>) -> Vec<&'a Syntax<'a>> {
    let nodes: Vec<NodeJson> = match serde_json::from_str(json) {
        Ok(n) => n,
        Err(_) => return vec![],
    };

    nodes
        .iter()
        .filter_map(|node| node_to_syntax(node, arena))
        .collect()
}
