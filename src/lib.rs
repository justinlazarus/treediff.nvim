use nvim_oxi as oxi;
use nvim_oxi::{Dictionary, Function, Object};
use std::fs;

/// Compute a simple line-level diff between two files and write ed-style output.
/// This is the stub — will be replaced with tree-sitter-aware diffing.
fn diff_files(old_path: String, new_path: String, out_path: String) -> oxi::Result<()> {
    let old_content = fs::read_to_string(&old_path).unwrap_or_default();
    let new_content = fs::read_to_string(&new_path).unwrap_or_default();

    let old_lines: Vec<&str> = old_content.lines().collect();
    let new_lines: Vec<&str> = new_content.lines().collect();

    // Stub: use a naive LCS-based diff to produce ed-style output
    let ed_diff = naive_diff(&old_lines, &new_lines);
    fs::write(&out_path, ed_diff).unwrap_or_default();

    Ok(())
}

/// Naive line diff producing ed-style commands.
/// Just enough to prove the diffexpr pipeline works.
fn naive_diff(old: &[&str], new: &[&str]) -> String {
    let lcs = lcs_table(old, new);
    let mut i = old.len();
    let mut j = new.len();

    // Collect matched pairs by backtracking through LCS
    let mut matched: Vec<(usize, usize)> = Vec::new();
    while i > 0 && j > 0 {
        if old[i - 1] == new[j - 1] {
            i -= 1;
            j -= 1;
            matched.push((i, j));
        } else if lcs[i - 1][j] >= lcs[i][j - 1] {
            i -= 1;
        } else {
            j -= 1;
        }
    }
    matched.reverse();

    // Build ed-style diff from the gaps between matched lines
    let mut result = String::new();
    let mut old_pos = 0;
    let mut new_pos = 0;

    for (oi, ni) in &matched {
        let del_count = oi - old_pos;
        let add_count = ni - new_pos;

        if del_count > 0 && add_count > 0 {
            // Change
            let old_start = old_pos + 1;
            let old_end = old_pos + del_count;
            let new_start = new_pos + 1;
            let new_end = new_pos + add_count;
            if old_start == old_end {
                result.push_str(&format!("{}c{},{}\n", old_start, new_start, new_end));
            } else if new_start == new_end {
                result.push_str(&format!("{},{}c{}\n", old_start, old_end, new_start));
            } else {
                result.push_str(&format!("{},{}c{},{}\n", old_start, old_end, new_start, new_end));
            }
            for k in old_pos..*oi {
                result.push_str(&format!("< {}\n", old[k]));
            }
            result.push_str("---\n");
            for k in new_pos..*ni {
                result.push_str(&format!("> {}\n", new[k]));
            }
        } else if del_count > 0 {
            let old_start = old_pos + 1;
            let old_end = old_pos + del_count;
            if old_start == old_end {
                result.push_str(&format!("{}d{}\n", old_start, new_pos));
            } else {
                result.push_str(&format!("{},{}d{}\n", old_start, old_end, new_pos));
            }
            for k in old_pos..*oi {
                result.push_str(&format!("< {}\n", old[k]));
            }
        } else if add_count > 0 {
            let new_start = new_pos + 1;
            let new_end = new_pos + add_count;
            if new_start == new_end {
                result.push_str(&format!("{}a{}\n", old_pos, new_start));
            } else {
                result.push_str(&format!("{}a{},{}\n", old_pos, new_start, new_end));
            }
            for k in new_pos..*ni {
                result.push_str(&format!("> {}\n", new[k]));
            }
        }

        old_pos = oi + 1;
        new_pos = ni + 1;
    }

    // Handle trailing unmatched lines
    let del_count = old.len() - old_pos;
    let add_count = new.len() - new_pos;
    if del_count > 0 && add_count > 0 {
        let old_start = old_pos + 1;
        let old_end = old.len();
        let new_start = new_pos + 1;
        let new_end = new.len();
        result.push_str(&format!("{},{}c{},{}\n", old_start, old_end, new_start, new_end));
        for k in old_pos..old.len() {
            result.push_str(&format!("< {}\n", old[k]));
        }
        result.push_str("---\n");
        for k in new_pos..new.len() {
            result.push_str(&format!("> {}\n", new[k]));
        }
    } else if del_count > 0 {
        let old_start = old_pos + 1;
        let old_end = old.len();
        result.push_str(&format!("{},{}d{}\n", old_start, old_end, new_pos));
        for k in old_pos..old.len() {
            result.push_str(&format!("< {}\n", old[k]));
        }
    } else if add_count > 0 {
        let new_start = new_pos + 1;
        let new_end = new.len();
        result.push_str(&format!("{}a{},{}\n", old_pos, new_start, new_end));
        for k in new_pos..new.len() {
            result.push_str(&format!("> {}\n", new[k]));
        }
    }

    result
}

fn lcs_table(old: &[&str], new: &[&str]) -> Vec<Vec<usize>> {
    let m = old.len();
    let n = new.len();
    let mut table = vec![vec![0usize; n + 1]; m + 1];
    for i in 1..=m {
        for j in 1..=n {
            if old[i - 1] == new[j - 1] {
                table[i][j] = table[i - 1][j - 1] + 1;
            } else {
                table[i][j] = table[i - 1][j].max(table[i][j - 1]);
            }
        }
    }
    table
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
