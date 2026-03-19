# treediff.nvim

Structural, token-level diffs for Neovim. Powered by the difftastic algorithm, using Neovim's own tree-sitter parsers.

## What it does

treediff replaces Neovim's line-level diff highlighting with **token-level** structural diffs. Changed tokens are highlighted in bold red (deleted) and bold green (added). Unchanged tokens within changed lines stay uncolored — just like difftastic.

When any buffer enters diff mode (`:diffthis`, fugitive, gitsigns, etc.), treediff automatically:
- Applies token-level red/green highlights
- Colors line numbers to match (red for deleted lines, green for added)
- Neutralizes Neovim's built-in DiffAdd/DiffChange background colors
- Stops syntax highlighting on diff buffers for a clean look

## Requirements

- Neovim >= 0.10
- Tree-sitter parsers installed (via nvim-treesitter or Neovim built-in)

No external tools required. The difftastic algorithm runs as a native library bundled with the plugin.

## Install

**vim.pack**
```lua
vim.pack.add('https://github.com/justinlazarus/treediff.nvim')
```

**lazy.nvim**
```lua
{ 'justinlazarus/treediff.nvim' }
```

## Setup

```lua
require('treediff').setup()
```

That's it. Diffs are enhanced automatically whenever `:diffthis` is used.

### Options

```lua
require('treediff').setup({
  auto_highlight = true,   -- Automatically enhance any :diffthis (default: true)
  use_diffexpr = false,    -- Use structural diff for line alignment (default: false)
  priority = 200,          -- Extmark priority (default: 200)
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:TreeDiff <old> <new>` | Open two files in a side-by-side diff view |
| `:TreeDiffOff` | Close the diff view and restore settings |
| `:TreeDiffTest` | Open a demo diff (Rust by default) |
| `:TreeDiffTest cs` | Open a demo diff with C# code |

## Supported Languages

Token-level diffs work for any language with a tree-sitter parser installed. Per-language configs (atom nodes, delimiter tokens) are included for ~60 languages including Rust, Lua, Python, JavaScript, TypeScript, C#, Go, C, C++, Java, Ruby, and many more.

## How it works

1. **Lua** parses both files using `vim.treesitter` (Neovim's built-in API)
2. **Lua** walks the parse trees, applying per-language configs, and serializes to JSON
3. **Rust** deserializes the JSON into the difftastic data structure, runs the full algorithm (mark_unchanged, Dijkstra graph search, fix_all_sliders), and returns novel tokens
4. **Lua** places extmarks on the diff buffers

The algorithm is a faithful port of [difftastic](https://difftastic.wilfred.me.uk/) with the same graph limit (3,000,000).

## License

MIT
