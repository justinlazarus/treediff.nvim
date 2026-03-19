# AGENTS.md — Outstanding Issues & Requirements

This file tracks requirements the user has stated that are not yet fully addressed.

## Architecture (Refactored)

The plugin now uses a **split architecture**:

1. **Lua side** (`tree_walker.lua`): Parses source code using `vim.treesitter` (Neovim's built-in tree-sitter API), walks the parse tree applying per-language configs (atom_nodes, delimiter_tokens), and serializes the result as JSON.

2. **Rust side** (`json_deserialize.rs` → diff pipeline): Deserializes the JSON into arena-allocated `Syntax` nodes, then runs the full difftastic algorithm (mark_unchanged → init_next_prev → dijkstra → fix_all_sliders).

3. **FFI boundary**: `treediff_diff_nodes(lhs_json, rhs_json, lang_name)` — Lua sends pre-built syntax trees, Rust returns token-level diff results as JSON.

**Key benefit**: Parsing uses the same tree-sitter parsers as Neovim itself (consistent with syntax highlighting). The old Rust-side parsing (`treediff_diff_tokens`) is retained as a fallback.

### Data Flow

```
Lua: vim.treesitter.get_string_parser(src, lang)
  → tree_walker.parse_to_json(src, lang)
  → JSON string of Syntax nodes
  → FFI: treediff_diff_nodes(lhs_json, rhs_json, lang_name)
  → Rust: json_deserialize → Arena<Syntax> → diff pipeline → token JSON
  → Lua: parse JSON → place extmarks
```

## Output Quality

- **Goal**: High-quality structural diffs, not necessarily byte-identical to `difft`.
- **Algorithm**: Full difftastic pipeline faithfully ported (graph limit 3,000,000).
- **Parser consistency**: Uses Neovim's own tree-sitter parsers, so diffs are consistent with what the editor "sees". May differ from `difft` for languages where grammar ABIs diverge.
- **Verified languages**: Rust, Lua, Python, JavaScript all produce correct structural diffs.

## Comprehensive Testing

Current: **31 passing tests** (8 diffview UI + 23 parity/unit).

Tests cover:
- Library loading, diff API, token format validation
- UI: TreeDiff/TreeDiffOff commands, extmark placement/cleanup
- Token-level correctness across 12 languages: Rust, Lua, Python, JavaScript, C#, TypeScript, CSS, JSON, YAML, Bash, HTML, TOML, SQL, Kotlin, TSX, XML
- tree_walker: JSON output validity, empty input handling
- Zero-width token filtering, identical file detection
- diffexpr integration (treediff_diff_files produces valid ed-style output)

Still needed:
- **Regression fixtures**: saved expected outputs for known inputs
- **Automated difft comparison**: script to compare with `difft` output

## UI Requirements (Implemented)

These have been implemented but should be verified after any changes:

- No syntax highlighting in diff windows (tree-sitter and vim syntax both disabled)
- No cursorline in diff windows
- No indent guide lines in diff windows (ibl disabled)
- No background highlights (DiffAdd, DiffChange, DiffText, DiffDelete all cleared)
- Only bold red (`#ff6e6e`) for deleted tokens, bold green (`#6eff6e`) for added tokens
- No underlines anywhere
- Blank filler lines (no dashes)
- `:TreeDiffOff` restores all original settings

## User Preferences

- Do not speculate or blame external dependencies without evidence
- Verify fixes actually work (headless testing) before asking user to test
- Be proactive — create test diffs, compare outputs, fix issues without being asked
- Do not use worktrees
- Do not ask for permission to do work that was already requested
