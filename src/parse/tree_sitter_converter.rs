//! Convert tree-sitter parse trees into difftastic's Syntax type.
//!
//! This is a faithful port of difftastic's tree_sitter_parser.rs conversion logic,
//! with per-language `TreeSitterConfig` containing `atom_nodes` and `delimiter_tokens`.
//! We skip sub-languages and highlight queries since we don't have that infrastructure.

use std::collections::HashSet;

use line_numbers::{LinePositions, SingleLineSpan};
use typed_arena::Arena;

use crate::parse::syntax::{AtomKind, StringKind, Syntax};

/// Configuration for how to convert a tree-sitter parse tree for a specific language.
pub struct TreeSitterConfig {
    /// Force these tree-sitter node kinds to be difftastic atoms,
    /// ignoring their children. This ensures correct diffs for nodes
    /// like string literals that have internal structure in tree-sitter
    /// but should be treated as opaque values by difftastic.
    pub atom_nodes: HashSet<&'static str>,

    /// Pairs of tokens that should be treated as list delimiters.
    /// Tree-sitter includes delimiter tokens as children, so we need
    /// to identify them to construct proper List nodes.
    pub delimiter_tokens: Vec<(&'static str, &'static str)>,
}

// Common OCaml atom nodes shared between OCaml and OCaml Interface.
const OCAML_ATOM_NODES: &[&str] = &[
    "character",
    "string",
    "quoted_string",
    "tag",
    "type_variable",
    "attribute_id",
];

/// Get the `TreeSitterConfig` for a given language name.
/// The language name should match what nvim-treesitter uses (e.g. "lua", "rust", "c_sharp").
pub fn config_for_language(lang_name: &str) -> TreeSitterConfig {
    match lang_name {
        "ada" => TreeSitterConfig {
            atom_nodes: ["string_literal", "character_literal"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]")],
        },
        "apex" => TreeSitterConfig {
            atom_nodes: [
                "string_literal",
                "null_literal",
                "boolean",
                "int",
                "decimal_floating_point_literal",
                "date_literal",
                "currency_literal",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("[", "]"), ("(", ")"), ("{", "}")],
        },
        "bash" => TreeSitterConfig {
            atom_nodes: ["string", "raw_string", "heredoc_body", "simple_expansion"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]")],
        },
        "c" => TreeSitterConfig {
            atom_nodes: ["string_literal", "char_literal"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]")],
        },
        "cpp" | "c_plus_plus" => TreeSitterConfig {
            atom_nodes: ["string_literal", "char_literal"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]"), ("<", ">")],
        },
        "clojure" => TreeSitterConfig {
            atom_nodes: ["kwd_lit", "regex_lit"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]")],
        },
        "cmake" => TreeSitterConfig {
            atom_nodes: ["argument"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")")],
        },
        "commonlisp" | "common_lisp" => TreeSitterConfig {
            atom_nodes: ["str_lit", "char_lit"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")")],
        },
        "c_sharp" => TreeSitterConfig {
            atom_nodes: [
                "string_literal",
                "verbatim_string_literal",
                "character_literal",
                "modifier",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")")],
        },
        "css" => TreeSitterConfig {
            atom_nodes: [
                "integer_value",
                "float_value",
                "color_value",
                "string_value",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")")],
        },
        "dart" => TreeSitterConfig {
            atom_nodes: ["string_literal", "script_tag"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]"), ("<", ">")],
        },
        "devicetree" => TreeSitterConfig {
            atom_nodes: ["byte_string_literal", "string_literal"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("<", ">"), ("{", "}"), ("(", ")")],
        },
        "elixir" => TreeSitterConfig {
            atom_nodes: ["string", "sigil", "heredoc"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("do", "end")],
        },
        "elm" => TreeSitterConfig {
            atom_nodes: ["string_constant_expr"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("[", "]"), ("(", ")")],
        },
        "elvish" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]"), ("|", "|")],
        },
        "elisp" | "emacs_lisp" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]")],
        },
        "erlang" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]")],
        },
        "fsharp" | "f_sharp" => TreeSitterConfig {
            atom_nodes: ["string", "triple_quoted_string"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("{", "}")],
        },
        "fortran" => TreeSitterConfig {
            atom_nodes: ["string_literal"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("(/", "/)"), ("[", "]")],
        },
        "gleam" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("{", "}")],
        },
        "go" => TreeSitterConfig {
            atom_nodes: ["interpreted_string_literal", "raw_string_literal"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("{", "}"), ("[", "]"), ("(", ")")],
        },
        "hack" => TreeSitterConfig {
            atom_nodes: ["prefixed_string", "heredoc"].into_iter().collect(),
            delimiter_tokens: vec![("[", "]"), ("(", ")"), ("<", ">"), ("{", "}")],
        },
        "hare" => TreeSitterConfig {
            atom_nodes: ["string_constant", "rune_constant"].into_iter().collect(),
            delimiter_tokens: vec![("[", "]"), ("(", ")"), ("{", "}")],
        },
        "haskell" => TreeSitterConfig {
            atom_nodes: [
                "qualified_variable",
                "qualified_module",
                "qualified_constructor",
                "strict_type",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("[", "]"), ("(", ")")],
        },
        "hcl" => TreeSitterConfig {
            atom_nodes: ["string_lit", "heredoc_template"].into_iter().collect(),
            delimiter_tokens: vec![
                ("[", "]"),
                ("(", ")"),
                ("{", "}"),
                ("%{", "}"),
                ("%{~", "~}"),
                ("${", "}"),
            ],
        },
        "html" => TreeSitterConfig {
            atom_nodes: [
                "doctype",
                "quoted_attribute_value",
                "raw_text",
                "tag_name",
                "text",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("<", ">"), ("<!", ">"), ("<!--", "-->")],
        },
        "janet" | "janet_simple" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![
                ("@{", "}"),
                ("@(", ")"),
                ("@[", "]"),
                ("{", "}"),
                ("(", ")"),
                ("[", "]"),
            ],
        },
        "java" => TreeSitterConfig {
            atom_nodes: [
                "string_literal",
                "boolean_type",
                "integral_type",
                "floating_point_type",
                "void_type",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]")],
        },
        "javascript" | "jsx" => TreeSitterConfig {
            atom_nodes: ["string", "template_string", "regex"].into_iter().collect(),
            delimiter_tokens: vec![("[", "]"), ("(", ")"), ("{", "}"), ("<", ">")],
        },
        "json" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("[", "]")],
        },
        "julia" => TreeSitterConfig {
            atom_nodes: [
                "string_literal",
                "prefixed_string_literal",
                "command_literal",
                "character_literal",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("{", "}"), ("[", "]"), ("(", ")")],
        },
        "kotlin" => TreeSitterConfig {
            atom_nodes: [
                "nullable_type",
                "string_literal",
                "line_string_literal",
                "character_literal",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]"), ("<", ">")],
        },
        "latex" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("{", "}"), ("[", "]")],
        },
        "lua" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]")],
        },
        "make" => TreeSitterConfig {
            atom_nodes: ["shell_text", "text"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")")],
        },
        "newick" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("(", ")")],
        },
        "nix" => TreeSitterConfig {
            atom_nodes: ["string_expression", "indented_string_expression"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("{", "}"), ("[", "]")],
        },
        "objc" | "objective_c" => TreeSitterConfig {
            atom_nodes: ["string_literal"].into_iter().collect(),
            delimiter_tokens: vec![
                ("(", ")"),
                ("{", "}"),
                ("[", "]"),
                ("@(", ")"),
                ("@{", "}"),
                ("@[", "]"),
            ],
        },
        "ocaml" => TreeSitterConfig {
            atom_nodes: OCAML_ATOM_NODES.iter().copied().collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("{", "}")],
        },
        "ocaml_interface" => TreeSitterConfig {
            atom_nodes: OCAML_ATOM_NODES.iter().copied().collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("{", "}")],
        },
        "pascal" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("(", ")"), ("[", "]")],
        },
        "perl" => TreeSitterConfig {
            atom_nodes: [
                "string_single_quoted",
                "string_double_quoted",
                "comments",
                "command_qx_quoted",
                "pattern_matcher_m",
                "regex_pattern_qr",
                "transliteration_tr_or_y",
                "substitution_pattern_s",
                "scalar_variable",
                "array_variable",
                "hash_variable",
                "hash_access_variable",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("(", ")"), ("{", "}"), ("[", "]")],
        },
        "php" => TreeSitterConfig {
            atom_nodes: ["string", "encapsed_string"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("{", "}")],
        },
        "proto" | "protobuf" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}")],
        },
        "python" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("{", "}")],
        },
        "qml" => TreeSitterConfig {
            atom_nodes: ["string", "template_string", "regex"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]"), ("<", ">")],
        },
        "r" => TreeSitterConfig {
            atom_nodes: ["string", "special"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]")],
        },
        "racket" => TreeSitterConfig {
            atom_nodes: ["string", "byte_string", "regex", "here_string"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]")],
        },
        "ruby" => TreeSitterConfig {
            atom_nodes: ["string", "heredoc_body", "regex"].into_iter().collect(),
            delimiter_tokens: vec![
                ("{", "}"),
                ("(", ")"),
                ("[", "]"),
                ("|", "|"),
                ("def", "end"),
                ("begin", "end"),
                ("class", "end"),
            ],
        },
        "rust" => TreeSitterConfig {
            atom_nodes: ["char_literal", "string_literal", "raw_string_literal"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]"), ("|", "|"), ("<", ">")],
        },
        "scala" => TreeSitterConfig {
            atom_nodes: [
                "string",
                "template_string",
                "interpolated_string_expression",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]")],
        },
        "scheme" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]")],
        },
        "scss" => TreeSitterConfig {
            atom_nodes: ["integer_value", "float_value", "color_value"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")")],
        },
        "smali" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![],
        },
        "solidity" => TreeSitterConfig {
            atom_nodes: ["string", "hex_string_literal", "unicode_string_literal"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("[", "]"), ("(", ")"), ("{", "}")],
        },
        "sql" => TreeSitterConfig {
            atom_nodes: ["string", "identifier"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")")],
        },
        "swift" => TreeSitterConfig {
            atom_nodes: ["line_string_literal"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]"), ("<", ">")],
        },
        "toml" => TreeSitterConfig {
            atom_nodes: ["string", "quoted_key"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("[", "]")],
        },
        "tsx" => TreeSitterConfig {
            atom_nodes: ["string", "template_string"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]"), ("<", ">")],
        },
        "typescript" => TreeSitterConfig {
            atom_nodes: ["string", "template_string", "regex", "predefined_type"]
                .into_iter()
                .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]"), ("<", ">")],
        },
        "xml" => TreeSitterConfig {
            atom_nodes: ["AttValue", "XMLDecl"].into_iter().collect(),
            delimiter_tokens: vec![("<", ">")],
        },
        "yaml" => TreeSitterConfig {
            atom_nodes: [
                "string_scalar",
                "double_quote_scalar",
                "single_quote_scalar",
                "block_scalar",
            ]
            .into_iter()
            .collect(),
            delimiter_tokens: vec![("{", "}"), ("(", ")"), ("[", "]")],
        },
        "verilog" => TreeSitterConfig {
            atom_nodes: ["integral_number"].into_iter().collect(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("begin", "end")],
        },
        "vhdl" => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("(", ")")],
        },
        "zig" => TreeSitterConfig {
            atom_nodes: ["string"].into_iter().collect(),
            delimiter_tokens: vec![("{", "}"), ("[", "]"), ("(", ")")],
        },
        // Default: no atom nodes, common delimiters. This gives reasonable
        // behavior for unknown languages.
        _ => TreeSitterConfig {
            atom_nodes: HashSet::new(),
            delimiter_tokens: vec![("(", ")"), ("[", "]"), ("{", "}")],
        },
    }
}

/// Convert a tree-sitter tree into difftastic Syntax nodes.
///
/// `lang_name` selects the per-language config (atom_nodes, delimiter_tokens).
pub fn to_syntax<'a>(
    tree: &tree_sitter::Tree,
    src: &str,
    arena: &'a Arena<Syntax<'a>>,
    lang_name: &str,
) -> Vec<&'a Syntax<'a>> {
    // Don't return anything on empty input. Most parsers return a
    // zero-width top-level AST node on empty files.
    if src.trim().is_empty() {
        return vec![];
    }

    let config = config_for_language(lang_name);
    let nl_pos = LinePositions::from(src);
    let mut cursor = tree.walk();

    // The tree always has a single root; we want its children.
    if !cursor.goto_first_child() {
        return vec![];
    }

    all_syntaxes_from_cursor(arena, src, &nl_pos, &mut cursor, &config)
}

/// Convert all tree-sitter nodes at this level to difftastic syntax nodes.
///
/// `cursor` should be pointing at the first tree-sitter node in a level.
fn all_syntaxes_from_cursor<'a>(
    arena: &'a Arena<Syntax<'a>>,
    src: &str,
    nl_pos: &LinePositions,
    cursor: &mut tree_sitter::TreeCursor,
    config: &TreeSitterConfig,
) -> Vec<&'a Syntax<'a>> {
    let mut nodes: Vec<&Syntax> = vec![];

    loop {
        if let Some(node) = syntax_from_cursor(arena, src, nl_pos, cursor, config) {
            nodes.push(node);
        }

        if !cursor.goto_next_sibling() {
            break;
        }
    }

    nodes
}

/// Convert the tree-sitter node at `cursor` to a difftastic syntax node.
///
/// This is the core dispatch function, ported from difftastic's `syntax_from_cursor`.
/// It checks:
/// 1. If the node kind is in `atom_nodes` -> treat as atom (ignore children)
/// 2. If the node has children -> treat as list
/// 3. Otherwise -> treat as atom (leaf node)
fn syntax_from_cursor<'a>(
    arena: &'a Arena<Syntax<'a>>,
    src: &str,
    nl_pos: &LinePositions,
    cursor: &mut tree_sitter::TreeCursor,
    config: &TreeSitterConfig,
) -> Option<&'a Syntax<'a>> {
    let node = cursor.node();

    if config.atom_nodes.contains(node.kind()) {
        // Treat nodes like string literals as atoms, regardless
        // of whether they have children.
        // atom_node hit
        atom_from_cursor(arena, src, nl_pos, cursor)
    } else if node.child_count() > 0 {
        Some(list_from_cursor(arena, src, nl_pos, cursor, config))
    } else {
        atom_from_cursor(arena, src, nl_pos, cursor)
    }
}

/// Get the text of each direct child as a token, or None if the child
/// is not a simple token (has multiple children or is an extra/comment node).
fn child_tokens<'a>(src: &'a str, cursor: &mut tree_sitter::TreeCursor) -> Vec<Option<&'a str>> {
    let mut tokens = vec![];

    cursor.goto_first_child();
    loop {
        let node = cursor.node();

        // We're only interested in tree-sitter nodes that are plain tokens,
        // not lists or comments.
        if node.child_count() > 1 || node.is_extra() {
            tokens.push(None);
        } else {
            tokens.push(Some(&src[node.start_byte()..node.end_byte()]));
        }

        if !cursor.goto_next_sibling() {
            break;
        }
    }
    cursor.goto_parent();

    tokens
}

/// Are any of the children of the node at `cursor` delimiters?
/// Return their indexes if so.
///
/// This searches for the first matching open delimiter token among children,
/// then finds the last matching close delimiter token after it.
fn find_delim_positions(
    src: &str,
    cursor: &mut tree_sitter::TreeCursor,
    lang_delims: &[(&str, &str)],
) -> Option<(usize, usize)> {
    let tokens = child_tokens(src, cursor);

    for (i, token) in tokens.iter().enumerate() {
        for (open_delim, close_delim) in lang_delims {
            if *token == Some(open_delim) {
                for (j, token) in tokens.iter().skip(i + 1).enumerate() {
                    if *token == Some(close_delim) {
                        return Some((i, i + 1 + j));
                    }
                }
            }
        }
    }

    None
}

/// Convert the tree-sitter node at `cursor` to a difftastic list node.
///
/// This is a faithful port of difftastic's `list_from_cursor`. It:
/// 1. Finds delimiter positions among children using `find_delim_positions`
/// 2. Splits children into before-delim, between-delim, and after-delim groups
/// 3. Creates an inner list with the delimiters and between-delim children
/// 4. If there are before/after children, wraps in an outer list
fn list_from_cursor<'a>(
    arena: &'a Arena<Syntax<'a>>,
    src: &str,
    nl_pos: &LinePositions,
    cursor: &mut tree_sitter::TreeCursor,
    config: &TreeSitterConfig,
) -> &'a Syntax<'a> {
    let root_node = cursor.node();

    // We may not have an enclosing delimiter for this list. Use "" as
    // the delimiter text and the start/end of this node as the
    // delimiter positions.
    let outer_open_content = "";
    let outer_open_position = nl_pos.from_region(root_node.start_byte(), root_node.start_byte());
    let outer_close_content = "";
    let outer_close_position = nl_pos.from_region(root_node.end_byte(), root_node.end_byte());

    let (i, j) = match find_delim_positions(src, cursor, &config.delimiter_tokens) {
        Some((i, j)) => (i as isize, j as isize),
        None => (-1, root_node.child_count() as isize),
    };

    let mut inner_open_content: &str = outer_open_content;
    let mut inner_open_position: Vec<SingleLineSpan> = outer_open_position.clone();
    let mut inner_close_content: &str = outer_close_content;
    let mut inner_close_position: Vec<SingleLineSpan> = outer_close_position.clone();

    // Tree-sitter trees include the delimiter tokens, so `(x)` is
    // parsed as: "(" "x" ")"
    //
    // However, there's no guarantee that the first token is a
    // delimiter. For example, the C parser treats `foo[0]` as:
    // "foo" "[" "0" "]"
    //
    // Store the syntax nodes before, between and after the
    // delimiters, so we can construct lists.
    let mut before_delim = vec![];
    let mut between_delim = vec![];
    let mut after_delim = vec![];

    let mut node_i: isize = 0;
    cursor.goto_first_child();
    loop {
        let node = cursor.node();
        if node_i < i {
            if let Some(s) = syntax_from_cursor(arena, src, nl_pos, cursor, config) {
                before_delim.push(s);
            }
        } else if node_i == i {
            inner_open_content = &src[node.start_byte()..node.end_byte()];
            inner_open_position = nl_pos.from_region(node.start_byte(), node.end_byte());
        } else if node_i < j {
            if let Some(s) = syntax_from_cursor(arena, src, nl_pos, cursor, config) {
                between_delim.push(s);
            }
        } else if node_i == j {
            inner_close_content = &src[node.start_byte()..node.end_byte()];
            inner_close_position = nl_pos.from_region(node.start_byte(), node.end_byte());
        } else if node_i > j {
            if let Some(s) = syntax_from_cursor(arena, src, nl_pos, cursor, config) {
                after_delim.push(s);
            }
        }

        if !cursor.goto_next_sibling() {
            break;
        }
        node_i += 1;
    }
    cursor.goto_parent();

    let inner_list = Syntax::new_list(
        arena,
        inner_open_content,
        inner_open_position,
        between_delim,
        inner_close_content,
        inner_close_position,
    );

    if before_delim.is_empty() && after_delim.is_empty() {
        // The common case "(" "x" ")", so we don't need the outer list.
        inner_list
    } else {
        // Wrap the inner list in an additional list that includes the
        // syntax nodes before and after the delimiters.
        //
        // "foo" "[" "0" "]" // tree-sitter nodes
        //
        // (List "foo" (List "0")) // difftastic syntax nodes
        let mut children = before_delim;
        children.push(inner_list);
        children.append(&mut after_delim);

        Syntax::new_list(
            arena,
            outer_open_content,
            outer_open_position,
            children,
            outer_close_content,
            outer_close_position,
        )
    }
}

/// Convert the tree-sitter node at `cursor` to a difftastic atom.
fn atom_from_cursor<'a>(
    arena: &'a Arena<Syntax<'a>>,
    src: &str,
    nl_pos: &LinePositions,
    cursor: &mut tree_sitter::TreeCursor,
) -> Option<&'a Syntax<'a>> {
    let node = cursor.node();
    let position = nl_pos.from_region(node.start_byte(), node.end_byte());
    let mut content = &src[node.start_byte()..node.end_byte()];

    // The C and C++ grammars have a '\n' node with the preprocessor.
    // This isn't useful for difftastic, because it's not visible.
    if node.kind() == "\n" {
        return None;
    }

    // JSX trims whitespace at the beginning and end of text nodes.
    if node.kind() == "jsx_text" {
        content = content.trim();
    }

    let kind = if node.is_error() {
        AtomKind::TreeSitterError
    } else if node.is_extra() || node.kind() == "comment" {
        // 'extra' nodes in tree-sitter are comments. Most parsers use
        // 'comment' as their comment node name.
        AtomKind::Comment
    } else {
        classify_atom(node, content)
    };

    Some(Syntax::new_atom(arena, position, content.to_owned(), kind))
}

/// Classify a leaf node as Comment, String, or Normal based on heuristics.
/// This is a fallback for when we don't have highlight query data.
fn classify_atom(node: tree_sitter::Node, content: &str) -> AtomKind {
    let kind = node.kind();

    // Detect comments by node kind
    if kind.contains("comment") {
        return AtomKind::Comment;
    }

    // Detect strings by node kind
    if kind.contains("string")
        || kind == "string_literal"
        || kind == "template_string"
        || kind == "raw_string_literal"
        || kind == "char_literal"
        || kind == "character_literal"
    {
        return AtomKind::String(StringKind::StringLiteral);
    }

    // Detect strings by content
    if (content.starts_with('"') && content.ends_with('"'))
        || (content.starts_with('\'') && content.ends_with('\''))
        || (content.starts_with('`') && content.ends_with('`'))
    {
        return AtomKind::String(StringKind::StringLiteral);
    }

    // Detect text content (XML CharData, HTML text)
    if kind == "CharData" || kind == "text" {
        return AtomKind::String(StringKind::Text);
    }

    AtomKind::Normal
}
