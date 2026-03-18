// No-op logging macros (difftastic uses log crate, we don't need it)
macro_rules! info { ($($arg:tt)*) => {} }
macro_rules! debug { ($($arg:tt)*) => {} }

mod diff;
mod hash;
mod lines;
mod parse;
mod words;

use nvim_oxi as oxi;
use nvim_oxi::{Dictionary, Function, Object};
use similar::DiffOp;
use std::fs;

/// Compute a line-level diff between two files and write ed-style output.
/// This will be replaced with tree-sitter-aware diffing.
fn diff_files(old_path: String, new_path: String, out_path: String) -> oxi::Result<()> {
    let old_content = fs::read_to_string(&old_path).unwrap_or_default();
    let new_content = fs::read_to_string(&new_path).unwrap_or_default();

    let diff = similar::TextDiff::from_lines(&old_content, &new_content);
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
                    let after = old_index; // 0-indexed position in old
                    let new_start = new_index + 1; // 1-indexed
                    let new_end = new_index + new_len;
                    if new_start == new_end {
                        result.push_str(&format!("{}a{}\n", after, new_start));
                    } else {
                        result.push_str(&format!("{}a{},{}\n", after, new_start, new_end));
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
                    let old_start = old_index + 1; // 1-indexed
                    let old_end = old_index + old_len;
                    let after = new_index; // position in new
                    if old_start == old_end {
                        result.push_str(&format!("{}d{}\n", old_start, after));
                    } else {
                        result.push_str(&format!("{},{}d{}\n", old_start, old_end, after));
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

    fs::write(&out_path, result).unwrap_or_default();
    Ok(())
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

    Dictionary::from_iter([("diff_files", Object::from(diff_fn))])
}
