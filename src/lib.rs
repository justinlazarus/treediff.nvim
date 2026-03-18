// No-op logging macros (difftastic uses log crate, we don't need it)
macro_rules! info { ($($arg:tt)*) => {} }
macro_rules! debug { ($($arg:tt)*) => {} }

mod diff;
mod hash;
mod lines;
mod parse;
mod treediff;
mod words;

use nvim_oxi as oxi;
use nvim_oxi::{Dictionary, Function, Object};
use std::fs;
use std::path::PathBuf;

/// Detect language from file extension and find the parser .so
fn detect_language(file_path: &str) -> Option<(String, PathBuf)> {
    let ext = std::path::Path::new(file_path)
        .extension()?
        .to_str()?;

    let lang_name = match ext {
        "rs" => "rust",
        "lua" => "lua",
        "py" => "python",
        "js" => "javascript",
        "jsx" => "javascript",
        "ts" => "typescript",
        "tsx" => "tsx",
        "c" => "c",
        "h" => "c",
        "cpp" | "cc" | "cxx" => "cpp",
        "hpp" | "hh" => "cpp",
        "cs" => "c_sharp",
        "go" => "go",
        "java" => "java",
        "rb" => "ruby",
        "sh" | "bash" => "bash",
        "json" => "json",
        "yaml" | "yml" => "yaml",
        "toml" => "toml",
        "html" | "htm" => "html",
        "css" => "css",
        "scss" => "scss",
        "md" => "markdown",
        "sql" => "sql",
        "swift" => "swift",
        "kt" | "kts" => "kotlin",
        "dart" => "dart",
        "zig" => "zig",
        "ex" | "exs" => "elixir",
        _ => return None,
    };

    // Search common Neovim parser locations
    let search_paths = vec![
        dirs_parser_path("site/pack/core/opt/nvim-treesitter/parser"),
        dirs_parser_path("site/pack/packer/start/nvim-treesitter/parser"),
        dirs_parser_path("lazy/nvim-treesitter/parser"),
    ];

    for base in search_paths.into_iter().flatten() {
        let parser_path = base.join(format!("{}.so", lang_name));
        if parser_path.exists() {
            return Some((lang_name.to_string(), parser_path));
        }
    }

    None
}

/// Get a parser directory path under Neovim's data dir.
fn dirs_parser_path(subpath: &str) -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let path = PathBuf::from(home)
        .join(".local/share/nvim")
        .join(subpath);
    if path.exists() {
        Some(path)
    } else {
        None
    }
}

/// Compute a diff between two files and write ed-style output.
fn diff_files(old_path: String, new_path: String, out_path: String) -> oxi::Result<()> {
    let old_content = fs::read_to_string(&old_path).unwrap_or_default();
    let new_content = fs::read_to_string(&new_path).unwrap_or_default();

    // Try to detect language and load tree-sitter parser
    let language = detect_language(&old_path)
        .or_else(|| detect_language(&new_path))
        .and_then(|(_, parser_path)| treediff::load_language(&parser_path));

    let result = treediff::structural_diff(&old_content, &new_content, language);
    fs::write(&out_path, result).unwrap_or_default();

    Ok(())
}

/// Convert a TokenInfo vec into a Lua-compatible array of tables.
fn tokens_to_object(tokens: &[treediff::TokenInfo]) -> Object {
    let arr: Vec<Object> = tokens
        .iter()
        .filter(|t| t.kind == treediff::TokenChange::Novel)
        .map(|t| {
            let dict = Dictionary::from_iter([
                ("line", Object::from(t.line as i64)),
                ("start_col", Object::from(t.start_col as i64)),
                ("end_col", Object::from(t.end_col as i64)),
            ]);
            Object::from(dict)
        })
        .collect();
    Object::from(nvim_oxi::Array::from_iter(arr))
}

/// Compute a structural diff and return token-level change data to Lua.
fn diff_tokens_lua(
    old_content: String,
    new_content: String,
    lang_name: String,
) -> oxi::Result<Object> {
    // Find the parser .so for this language
    let search_paths = vec![
        dirs_parser_path("site/pack/core/opt/nvim-treesitter/parser"),
        dirs_parser_path("site/pack/packer/start/nvim-treesitter/parser"),
        dirs_parser_path("lazy/nvim-treesitter/parser"),
    ];

    let mut language = None;
    for base in search_paths.into_iter().flatten() {
        let parser_path = base.join(format!("{}.so", lang_name));
        if parser_path.exists() {
            language = treediff::load_language(&parser_path);
            break;
        }
    }

    match treediff::diff_tokens(&old_content, &new_content, language) {
        Some(result) => {
            let dict = Dictionary::from_iter([
                ("lhs_tokens", tokens_to_object(&result.lhs_tokens)),
                ("rhs_tokens", tokens_to_object(&result.rhs_tokens)),
            ]);
            Ok(Object::from(dict))
        }
        None => Ok(Object::nil()),
    }
}

/// Plugin entry point. Exposes functions to Lua.
#[oxi::plugin]
fn treediff_native() -> Dictionary {
    let diff_fn: Function<(String, String, String), ()> = Function::from_fn(
        |(old_path, new_path, out_path): (String, String, String)| {
            diff_files(old_path, new_path, out_path)?;
            Ok::<(), oxi::Error>(())
        },
    );

    let diff_tokens_fn: Function<(String, String, String), Object> = Function::from_fn(
        |(old_content, new_content, lang_name): (String, String, String)| {
            diff_tokens_lua(old_content, new_content, lang_name)
        },
    );

    Dictionary::from_iter([
        ("diff_files", Object::from(diff_fn)),
        ("diff_tokens", Object::from(diff_tokens_fn)),
    ])
}
