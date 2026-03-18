local M = {}

--- Load the native Rust module.
--- Returns nil if not compiled yet.
local function load_native()
  -- Add the plugin's lua/ dir to cpath so require finds the .so
  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local so_path = plugin_dir .. "/treediff_native.so"
  if not package.cpath:find(plugin_dir, 1, true) then
    package.cpath = plugin_dir .. "/?.so;" .. package.cpath
  end
  local ok, native = pcall(require, "treediff_native")
  if ok then return native end
  return nil
end

--- Set up treediff as the diffexpr.
function M.setup()
  local native = load_native()
  if not native then
    vim.notify("treediff: native module not found — run `cargo build --release`", vim.log.levels.WARN)
    return
  end

  M._native = native

  -- Register as Neovim's diff engine
  vim.o.diffexpr = "v:lua.TreeDiffExpr()"

  -- Global function called by diffexpr
  _G.TreeDiffExpr = function()
    local old_file = vim.v.fname_in
    local new_file = vim.v.fname_new
    local out_file = vim.v.fname_out
    local ok, err = pcall(M._native.diff_files, old_file, new_file, out_file)
    if not ok then
      -- Fallback: system diff
      vim.fn.system("diff " .. vim.fn.shellescape(old_file) .. " " .. vim.fn.shellescape(new_file) .. " > " .. vim.fn.shellescape(out_file))
    end
  end
end

--- Diff two strings and return token-level change data.
--- Returns only novel (changed) tokens — unchanged tokens are omitted.
--- @param old_content string
--- @param new_content string
--- @param lang string  Tree-sitter language name (e.g. "lua", "c_sharp", "rust")
--- @return table|nil  { lhs_tokens = {{line, start_col, end_col}, ...}, rhs_tokens = {...} }
function M.diff(old_content, new_content, lang)
  if not M._native then
    local native = load_native()
    if not native then return nil end
    M._native = native
  end
  local ok, result = pcall(M._native.diff_tokens, old_content, new_content, lang)
  if not ok or result == nil then return nil end
  return result
end

return M
