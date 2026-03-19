local M = {}
local treediff = require("treediff")
local ft_map = require("treediff.ft_map")

local ns = vim.api.nvim_create_namespace("treediff")

-- Default highlight groups (user can override, diffview.lua sets these on open)
vim.api.nvim_set_hl(0, "TreeDiffAdd", { fg = "#6eff6e", bold = true, default = true })
vim.api.nvim_set_hl(0, "TreeDiffDelete", { fg = "#ff6e6e", bold = true, default = true })
vim.api.nvim_set_hl(0, "TreeDiffAddNr", { fg = "#6eff6e", bold = true, default = true })
vim.api.nvim_set_hl(0, "TreeDiffDeleteNr", { fg = "#ff6e6e", bold = true, default = true })

local priority = 200

function M.set_priority(p)
  priority = p
end

--- Resolve the tree-sitter language for a buffer.
local function buf_lang(bufnr)
  local ft = vim.bo[bufnr].filetype
  return ft_map[ft] or ft
end

--- Place extmarks for Novel tokens and color their line numbers.
--- @param bufnr number
--- @param tokens table[]  each { line, start_col, end_col }
--- @param hl_group string
--- @param nr_hl_group string
local function place_marks(bufnr, tokens, hl_group, nr_hl_group)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local nr_lines = {} -- track which lines already have a number highlight
  for _, tok in ipairs(tokens) do
    if tok.line < line_count then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, tok.line, tok.start_col, {
        end_col = tok.end_col,
        hl_group = hl_group,
        priority = priority,
      })
      -- Color the line number (once per line)
      if not nr_lines[tok.line] then
        nr_lines[tok.line] = true
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, tok.line, 0, {
          number_hl_group = nr_hl_group,
          priority = priority,
        })
      end
    end
  end
end

--- Context lines around each hunk for structural diff.
local CONTEXT = 3

--- Maximum lines to send to the structural diff per hunk.
local MAX_HUNK_LINES = 500

--- Extract changed regions from a unified diff string.
--- Returns a list of {lhs_start, lhs_count, rhs_start, rhs_count} (0-indexed).
--- @param diff_str string  Output of vim.diff()
--- @return table[]
local function parse_hunks(diff_str)
  local hunks = {}
  for line in diff_str:gmatch("[^\n]+") do
    local ls, lc, rs, rc = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
    if ls then
      table.insert(hunks, {
        lhs_start = tonumber(ls) - 1, -- 0-indexed
        lhs_count = tonumber(lc) or 1,
        rhs_start = tonumber(rs) - 1,
        rhs_count = tonumber(rc) or 1,
      })
    end
  end
  return hunks
end

--- Offset token positions by a line delta, filtering to a valid range.
--- Only keeps tokens whose original (pre-offset) line falls within [min_line, max_line).
--- @param tokens table[]
--- @param delta number  Line offset to add
--- @param min_line number  Minimum original line (inclusive, 0-indexed)
--- @param max_line number  Maximum original line (exclusive, 0-indexed)
--- @return table[]
local function offset_tokens(tokens, delta, min_line, max_line)
  local out = {}
  for _, t in ipairs(tokens) do
    if t.line >= min_line and t.line < max_line then
      out[#out + 1] = { line = t.line + delta, start_col = t.start_col, end_col = t.end_col }
    end
  end
  return out
end

--- Apply token-level diff highlights to two buffers.
--- Uses vim.diff() to find changed regions, then runs structural diff
--- on each hunk individually. This keeps large files fast.
--- @param lhs_bufnr number
--- @param rhs_bufnr number
function M.apply(lhs_bufnr, rhs_bufnr)
  M.clear(lhs_bufnr)
  M.clear(rhs_bufnr)

  local lang = buf_lang(lhs_bufnr)
  local lhs_lines = vim.api.nvim_buf_get_lines(lhs_bufnr, 0, -1, false)
  local rhs_lines = vim.api.nvim_buf_get_lines(rhs_bufnr, 0, -1, false)
  local lhs_text = table.concat(lhs_lines, "\n") .. "\n"
  local rhs_text = table.concat(rhs_lines, "\n") .. "\n"

  if lhs_text == "\n" and rhs_text == "\n" then return end

  -- For small files, diff the whole thing directly
  local total = #lhs_lines + #rhs_lines
  if total <= 2000 then
    local result = treediff.diff(lhs_text, rhs_text, lang)
    if not result then return end
    if result.lhs_tokens then
      place_marks(lhs_bufnr, result.lhs_tokens, "TreeDiffDelete", "TreeDiffDeleteNr")
    end
    if result.rhs_tokens then
      place_marks(rhs_bufnr, result.rhs_tokens, "TreeDiffAdd", "TreeDiffAddNr")
    end
    return
  end

  -- For large files, find changed hunks and diff each one separately
  local ok, diff_str = pcall(vim.diff, lhs_text, rhs_text, { result_type = "unified", ctxlen = 0 })
  if not ok or not diff_str or diff_str == "" then return end

  local hunks = parse_hunks(diff_str)
  if #hunks == 0 then return end

  for _, hunk in ipairs(hunks) do
    -- Expand hunk with context for better structural matching
    local lhs_start = math.max(0, hunk.lhs_start - CONTEXT)
    local lhs_end = math.min(#lhs_lines, hunk.lhs_start + hunk.lhs_count + CONTEXT)
    local rhs_start = math.max(0, hunk.rhs_start - CONTEXT)
    local rhs_end = math.min(#rhs_lines, hunk.rhs_start + hunk.rhs_count + CONTEXT)

    -- Skip extremely large hunks
    if (lhs_end - lhs_start) + (rhs_end - rhs_start) > MAX_HUNK_LINES then
      goto continue
    end

    -- Extract hunk lines
    local lhs_chunk = {}
    for i = lhs_start + 1, lhs_end do lhs_chunk[#lhs_chunk + 1] = lhs_lines[i] end
    local rhs_chunk = {}
    for i = rhs_start + 1, rhs_end do rhs_chunk[#rhs_chunk + 1] = rhs_lines[i] end

    local lhs_chunk_text = table.concat(lhs_chunk, "\n")
    local rhs_chunk_text = table.concat(rhs_chunk, "\n")

    -- The actual hunk range within the chunk (excluding context lines)
    local lhs_hunk_start_in_chunk = hunk.lhs_start - lhs_start  -- 0-indexed line in chunk
    local lhs_hunk_end_in_chunk = lhs_hunk_start_in_chunk + hunk.lhs_count
    local rhs_hunk_start_in_chunk = hunk.rhs_start - rhs_start
    local rhs_hunk_end_in_chunk = rhs_hunk_start_in_chunk + hunk.rhs_count

    local result = treediff.diff(lhs_chunk_text, rhs_chunk_text, lang)
    if result then
      if result.lhs_tokens then
        place_marks(lhs_bufnr,
          offset_tokens(result.lhs_tokens, lhs_start, lhs_hunk_start_in_chunk, lhs_hunk_end_in_chunk),
          "TreeDiffDelete", "TreeDiffDeleteNr")
      end
      if result.rhs_tokens then
        place_marks(rhs_bufnr,
          offset_tokens(result.rhs_tokens, rhs_start, rhs_hunk_start_in_chunk, rhs_hunk_end_in_chunk),
          "TreeDiffAdd", "TreeDiffAddNr")
      end
    end

    ::continue::
  end
end

--- Attach token highlights and re-apply on text changes.
--- @param lhs_bufnr number
--- @param rhs_bufnr number
function M.attach(lhs_bufnr, rhs_bufnr)
  M.apply(lhs_bufnr, rhs_bufnr)

  local group = vim.api.nvim_create_augroup("treediff_highlight", { clear = true })
  for _, bufnr in ipairs({ lhs_bufnr, rhs_bufnr }) do
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        M.apply(lhs_bufnr, rhs_bufnr)
      end,
    })
  end
end

--- Clear treediff extmarks from a buffer.
--- @param bufnr number
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Return the namespace id (useful for tests).
function M.namespace()
  return ns
end

return M
