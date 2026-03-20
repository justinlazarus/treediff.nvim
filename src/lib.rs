// No-op logging macros (difftastic uses log crate, we don't need it)
macro_rules! info {
    ($($arg:tt)*) => {};
}
macro_rules! debug {
    ($($arg:tt)*) => {};
}

mod diff;
mod hash;
mod lines;
mod parse;
mod treediff;
mod words;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;

/// Detect language from file extension and find the parser .so
fn detect_language(file_path: &str) -> Option<(String, PathBuf)> {
    let ext = std::path::Path::new(file_path).extension()?.to_str()?;

    let lang_name = match ext {
        "rs" => "rust",
        "lua" => "lua",
        "py" => "python",
        "js" => "javascript",
        "jsx" => "javascript",
        "ts" => "typescript",
        "tsx" => "tsx",
        "c" | "h" => "c",
        "cpp" | "cc" | "cxx" | "hpp" | "hh" => "cpp",
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

    let home = std::env::var("HOME").ok()?;
    let search_dirs = [
        "site/pack/core/opt/nvim-treesitter/parser",
        "site/pack/packer/start/nvim-treesitter/parser",
        "lazy/nvim-treesitter/parser",
    ];
    for subpath in &search_dirs {
        let p = PathBuf::from(&home)
            .join(".local/share/nvim")
            .join(subpath)
            .join(format!("{}.so", lang_name));
        if p.exists() {
            return Some((lang_name.to_string(), p));
        }
    }
    None
}

// ── C API for Lua FFI ──────────────────────────────────────────────

/// Diff two files, write ed-style output. Returns 0 on success.
#[no_mangle]
pub extern "C" fn treediff_diff_files(
    old_path: *const c_char,
    new_path: *const c_char,
    out_path: *const c_char,
) -> i32 {
    let old_path = unsafe { CStr::from_ptr(old_path) }.to_str().unwrap_or("");
    let new_path = unsafe { CStr::from_ptr(new_path) }.to_str().unwrap_or("");
    let out_path = unsafe { CStr::from_ptr(out_path) }.to_str().unwrap_or("");

    let old_content = std::fs::read_to_string(old_path).unwrap_or_default();
    let new_content = std::fs::read_to_string(new_path).unwrap_or_default();

    let detected = detect_language(old_path).or_else(|| detect_language(new_path));
    let lang_name_owned = detected
        .as_ref()
        .map(|(n, _)| n.clone())
        .unwrap_or_default();
    let language =
        detected.and_then(|(name, parser_path)| treediff::load_language(&parser_path, &name));

    let result = treediff::structural_diff(&old_content, &new_content, language, &lang_name_owned);
    std::fs::write(out_path, result).unwrap_or_default();
    0
}

/// Diff two strings, return JSON with token-level changes.
/// Caller must free the returned string with treediff_free.
#[no_mangle]
pub extern "C" fn treediff_diff_tokens(
    old_src: *const c_char,
    new_src: *const c_char,
    lang_name: *const c_char,
) -> *mut c_char {
    let old_src = unsafe { CStr::from_ptr(old_src) }.to_str().unwrap_or("");
    let new_src = unsafe { CStr::from_ptr(new_src) }.to_str().unwrap_or("");
    let lang_name = unsafe { CStr::from_ptr(lang_name) }.to_str().unwrap_or("");

    // Find parser
    let home = std::env::var("HOME").unwrap_or_default();
    let search_dirs = [
        "site/pack/core/opt/nvim-treesitter/parser",
        "site/pack/packer/start/nvim-treesitter/parser",
        "lazy/nvim-treesitter/parser",
    ];
    let mut language = None;
    for subpath in &search_dirs {
        let p = PathBuf::from(&home)
            .join(".local/share/nvim")
            .join(subpath)
            .join(format!("{}.so", lang_name));
        if p.exists() {
            language = treediff::load_language(&p, lang_name);
            break;
        }
    }

    let result = match treediff::diff_tokens(old_src, new_src, language, lang_name) {
        Some(r) => r,
        None => return std::ptr::null_mut(),
    };

    // Serialize to JSON
    #[derive(serde::Serialize)]
    struct TokenOut {
        line: usize,
        start_col: usize,
        end_col: usize,
    }
    #[derive(serde::Serialize)]
    struct DiffOut {
        lhs_tokens: Vec<TokenOut>,
        rhs_tokens: Vec<TokenOut>,
        anchors: Vec<(usize, usize)>,
    }

    let out = DiffOut {
        lhs_tokens: result
            .lhs_tokens
            .iter()
            .filter(|t| t.kind == treediff::TokenChange::Novel && t.end_col > t.start_col)
            .map(|t| TokenOut {
                line: t.line,
                start_col: t.start_col,
                end_col: t.end_col,
            })
            .collect(),
        rhs_tokens: result
            .rhs_tokens
            .iter()
            .filter(|t| t.kind == treediff::TokenChange::Novel && t.end_col > t.start_col)
            .map(|t| TokenOut {
                line: t.line,
                start_col: t.start_col,
                end_col: t.end_col,
            })
            .collect(),
        anchors: result.anchors,
    };

    let json = serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string());
    CString::new(json)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Diff two pre-built syntax trees (JSON from Lua's tree_walker.lua).
/// Returns JSON with token-level changes. Caller must free with treediff_free.
/// Returns null on error (including panics) — never crashes the host process.
#[no_mangle]
pub extern "C" fn treediff_diff_nodes(
    lhs_json: *const c_char,
    rhs_json: *const c_char,
    lang_name: *const c_char,
) -> *mut c_char {
    // Catch any panic so we never crash Neovim
    let result = std::panic::catch_unwind(|| {
        let lhs_json = unsafe { CStr::from_ptr(lhs_json) }.to_str().unwrap_or("[]");
        let rhs_json = unsafe { CStr::from_ptr(rhs_json) }.to_str().unwrap_or("[]");
        let lang_name = unsafe { CStr::from_ptr(lang_name) }.to_str().unwrap_or("");

        let result = match treediff::diff_tokens_from_json(lhs_json, rhs_json, lang_name) {
            Some(r) => r,
            None => return std::ptr::null_mut(),
        };

        #[derive(serde::Serialize)]
        struct TokenOut {
            line: usize,
            start_col: usize,
            end_col: usize,
        }
        #[derive(serde::Serialize)]
        struct DiffOut {
            lhs_tokens: Vec<TokenOut>,
            rhs_tokens: Vec<TokenOut>,
            anchors: Vec<(usize, usize)>,
        }

        let out = DiffOut {
            lhs_tokens: result
                .lhs_tokens
                .iter()
                .filter(|t| t.kind == treediff::TokenChange::Novel && t.end_col > t.start_col)
                .map(|t| TokenOut {
                    line: t.line,
                    start_col: t.start_col,
                    end_col: t.end_col,
                })
                .collect(),
            rhs_tokens: result
                .rhs_tokens
                .iter()
                .filter(|t| t.kind == treediff::TokenChange::Novel && t.end_col > t.start_col)
                .map(|t| TokenOut {
                    line: t.line,
                    start_col: t.start_col,
                    end_col: t.end_col,
                })
                .collect(),
            anchors: result.anchors,
        };

        let json = serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string());
        CString::new(json)
            .map(|s| s.into_raw())
            .unwrap_or(std::ptr::null_mut())
    });

    result.unwrap_or(std::ptr::null_mut())
}

/// Free a string returned by treediff_diff_tokens or treediff_diff_nodes.
#[no_mangle]
pub extern "C" fn treediff_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}
