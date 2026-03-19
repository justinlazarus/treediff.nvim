local M = {}
local treediff = require("treediff")
local ft_map = require("treediff.ft_map")

local ns = vim.api.nvim_create_namespace("treediff")

-- Default highlight groups (user can override, diffview.lua sets these on open)
vim.api.nvim_set_hl(0, "TreeDiffAdd", { fg = "#6eff6e", bold = true, default = true })
vim.api.nvim_set_hl(0, "TreeDiffDelete", { fg = "#ff6e6e", bold = true, default = true })

local priority = 200

function M.set_priority(p)
  priority = p
end

--- Resolve the tree-sitter language for a buffer.
local function buf_lang(bufnr)
  local ft = vim.bo[bufnr].filetype
  return ft_map[ft] or ft
end

--- Place extmarks for Novel tokens.
--- @param bufnr number
--- @param tokens table[]  each { line, start_col, end_col }
--- @param hl_group string
local function place_marks(bufnr, tokens, hl_group)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, tok in ipairs(tokens) do
    if tok.line < line_count then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, tok.line, tok.start_col, {
        end_col = tok.end_col,
        hl_group = hl_group,
        priority = priority,
      })
    end
  end
end

--- Apply token-level diff highlights to two buffers.
--- @param lhs_bufnr number
--- @param rhs_bufnr number
function M.apply(lhs_bufnr, rhs_bufnr)
  M.clear(lhs_bufnr)
  M.clear(rhs_bufnr)

  local lang = buf_lang(lhs_bufnr)
  local lhs_lines = vim.api.nvim_buf_get_lines(lhs_bufnr, 0, -1, false)
  local rhs_lines = vim.api.nvim_buf_get_lines(rhs_bufnr, 0, -1, false)
  local lhs_text = table.concat(lhs_lines, "\n")
  local rhs_text = table.concat(rhs_lines, "\n")

  if lhs_text == "" and rhs_text == "" then return end

  local result = treediff.diff(lhs_text, rhs_text, lang)
  if not result then return end

  -- Bold red on deleted tokens (LHS), bold green on added tokens (RHS)
  -- No filtering needed — the structural diff from Rust tells us exactly
  -- which tokens are Novel. No background highlights to compete with.
  if result.lhs_tokens then
    place_marks(lhs_bufnr, result.lhs_tokens, "TreeDiffDelete")
  end
  if result.rhs_tokens then
    place_marks(rhs_bufnr, result.rhs_tokens, "TreeDiffAdd")
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
