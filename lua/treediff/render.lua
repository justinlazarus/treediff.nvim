--- Render aligned diff buffers with token highlights, scrollbind, and navigation.
local M = {}
local highlight = require("treediff.highlight")

local ns = highlight.namespace()

--- Write padded text into a buffer and apply token highlights + filler styling.
--- @param win number  window handle
--- @param padded table[]  array of { text, orig } entries
--- @param tokens table[]  token list from diff result (0-indexed file lines)
--- @param file_to_buf table  { [0-indexed_file_line] = 1-indexed_buf_row }
--- @param hl_group string  e.g. "TreeDiffDelete" or "TreeDiffAdd"
--- @param nr_hl_group string  e.g. "TreeDiffDeleteNr" or "TreeDiffAddNr"
--- @param buf_to_file table  { [1-indexed_buf_row] = 0-indexed_file_line }
local function write_buffer(win, padded, tokens, file_to_buf, hl_group, nr_hl_group, buf_to_file)
  local bufnr = vim.api.nvim_win_get_buf(win)

  -- Build text lines
  local lines = {}
  for i, entry in ipairs(padded) do
    lines[i] = entry.text
  end

  -- Write into buffer
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].modified = false

  -- Store maps as buffer variables
  vim.b[bufnr].treediff_buf_to_file = buf_to_file
  vim.b[bufnr].treediff_file_to_buf = file_to_buf

  -- Place token extmarks (translate file lines to buffer rows)
  highlight.place_marks_mapped(bufnr, tokens, hl_group, nr_hl_group, file_to_buf)

  -- Highlight filler rows
  vim.api.nvim_set_hl(0, "TreeDiffFiller", { bg = "#1a1a2e", default = true })
  for i, entry in ipairs(padded) do
    if not entry.orig then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, i - 1, 0, {
        end_row = i - 1,
        end_col = 0,
        hl_eol = true,
        hl_group = "TreeDiffFiller",
        priority = 50,
      })
    end
  end
end

--- Set up scrollbind, cursorbind, and window options.
--- @param win number
--- @param bufnr number
local function setup_window(win, bufnr)
  vim.wo[win].scrollbind = true
  vim.wo[win].cursorbind = true
  vim.wo[win].diff = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].colorcolumn = ""
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].foldmethod = "manual"
  vim.wo[win].foldlevel = 999

  -- Custom statuscolumn showing original file line numbers
  vim.wo[win].statuscolumn = "%!v:lua.TreeDiffLineNr()"

  -- Stop treesitter and syntax highlighting
  pcall(vim.treesitter.stop, bufnr)
  vim.bo[bufnr].syntax = ""
end

--- Set up ]c / [c navigation keymaps for jumping between changed regions.
--- @param bufnr number
--- @param tokens table[]  novel tokens (0-indexed file lines)
--- @param file_to_buf table
local function setup_navigation(bufnr, tokens, file_to_buf)
  -- Collect buffer rows that have novel tokens
  local novel_rows = {}
  local seen = {}
  for _, tok in ipairs(tokens) do
    local buf_row = file_to_buf[tok.line]
    if buf_row and not seen[buf_row] then
      seen[buf_row] = true
      novel_rows[#novel_rows + 1] = buf_row
    end
  end
  table.sort(novel_rows)

  vim.keymap.set("n", "]c", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cur_row = cursor[1]  -- 1-indexed
    for _, row in ipairs(novel_rows) do
      if row > cur_row then
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        return
      end
    end
  end, { buffer = bufnr, desc = "Next treediff change" })

  vim.keymap.set("n", "[c", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cur_row = cursor[1]
    for i = #novel_rows, 1, -1 do
      if novel_rows[i] < cur_row then
        vim.api.nvim_win_set_cursor(0, { novel_rows[i], 0 })
        return
      end
    end
  end, { buffer = bufnr, desc = "Previous treediff change" })
end

--- Global function for statuscolumn: show original file line number or blank for fillers.
function _G.TreeDiffLineNr()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.v.lnum  -- 1-indexed
  local map = vim.b[bufnr].treediff_buf_to_file
  if map and map[lnum] then
    -- Show 1-indexed original line number, right-aligned in 4 chars
    return string.format("%4d ", map[lnum] + 1)
  else
    return "     "
  end
end

--- Render aligned diff into two windows.
--- @param lhs_win number
--- @param rhs_win number
--- @param lhs_padded table[]
--- @param rhs_padded table[]
--- @param diff_result table  { lhs_tokens, rhs_tokens }
--- @param lhs_maps table  { buf_to_file, file_to_buf }
--- @param rhs_maps table  { buf_to_file, file_to_buf }
function M.render(lhs_win, rhs_win, lhs_padded, rhs_padded, diff_result, lhs_maps, rhs_maps)
  local lhs_bufnr = vim.api.nvim_win_get_buf(lhs_win)
  local rhs_bufnr = vim.api.nvim_win_get_buf(rhs_win)

  -- Clear previous highlights
  highlight.clear(lhs_bufnr)
  highlight.clear(rhs_bufnr)

  -- Highlight groups
  vim.api.nvim_set_hl(0, "TreeDiffDelete", { fg = "#ff6e6e", bold = true })
  vim.api.nvim_set_hl(0, "TreeDiffAdd", { fg = "#6eff6e", bold = true })
  vim.api.nvim_set_hl(0, "TreeDiffDeleteNr", { fg = "#ff6e6e", bold = true })
  vim.api.nvim_set_hl(0, "TreeDiffAddNr", { fg = "#6eff6e", bold = true })

  -- Write padded content and apply highlights
  write_buffer(
    lhs_win, lhs_padded,
    diff_result.lhs_tokens or {},
    lhs_maps.file_to_buf,
    "TreeDiffDelete", "TreeDiffDeleteNr",
    lhs_maps.buf_to_file
  )
  write_buffer(
    rhs_win, rhs_padded,
    diff_result.rhs_tokens or {},
    rhs_maps.file_to_buf,
    "TreeDiffAdd", "TreeDiffAddNr",
    rhs_maps.buf_to_file
  )

  -- Set up window options
  setup_window(lhs_win, lhs_bufnr)
  setup_window(rhs_win, rhs_bufnr)

  -- Set up navigation keymaps
  setup_navigation(lhs_bufnr, diff_result.lhs_tokens or {}, lhs_maps.file_to_buf)
  setup_navigation(rhs_bufnr, diff_result.rhs_tokens or {}, rhs_maps.file_to_buf)

  -- Sync scroll position
  vim.cmd("syncbind")
end

--- Clean up render state from windows/buffers.
--- @param wins table  list of window handles
function M.cleanup(wins)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local bufnr = vim.api.nvim_win_get_buf(win)
      highlight.clear(bufnr)
      vim.wo[win].scrollbind = false
      vim.wo[win].cursorbind = false
      vim.wo[win].statuscolumn = ""
      -- Remove buffer-local keymaps
      pcall(vim.keymap.del, "n", "]c", { buffer = bufnr })
      pcall(vim.keymap.del, "n", "[c", { buffer = bufnr })
    end
  end
end

return M
