local M = {}
local ffi = require("ffi")

pcall(ffi.cdef, [[
  int treediff_diff_files(const char *old_path, const char *new_path, const char *out_path);
  char *treediff_diff_tokens(const char *old_src, const char *new_src, const char *lang_name);
  char *treediff_diff_nodes(const char *lhs_json, const char *rhs_json, const char *lang_name);
  void treediff_free(char *ptr);
]])

--- Load the native library.
local lib
local function load_lib()
  if lib then return lib end

  -- Find the native lib by searching runtimepath
  local candidates = {}
  for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
    table.insert(candidates, rtp .. "/lib/treediff_native.so")
    table.insert(candidates, rtp .. "/lib/treediff_native.dylib")
    table.insert(candidates, rtp .. "/target/release/libtreediff.dylib")
  end
  for _, candidate in ipairs(candidates) do
    if vim.fn.filereadable(candidate) == 1 then
      local ok, l = pcall(ffi.load, candidate)
      if ok then
        lib = l
        return lib
      end
    end
  end
  return nil
end

--- Default config.
M.config = {
  auto_highlight = true,
  use_diffexpr = false,
  priority = 200,
}

--- Set up treediff with optional config.
--- @param opts? table  { auto_highlight = bool, use_diffexpr = bool, priority = number }
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local native = load_lib()
  if not native then return end

  M._native = native

  -- Only override diffexpr if explicitly requested; Neovim's built-in diff
  -- handles line alignment correctly — our value-add is token extmarks.
  if M.config.use_diffexpr then
    vim.o.diffexpr = "v:lua.TreeDiffExpr()"
    _G.TreeDiffExpr = function()
      local old_file = vim.v.fname_in
      local new_file = vim.v.fname_new
      local out_file = vim.v.fname_out
      native.treediff_diff_files(old_file, new_file, out_file)
    end
  end

  local highlight = require("treediff.highlight")
  highlight.set_priority(M.config.priority)

  if M.config.auto_highlight then
    vim.api.nvim_create_autocmd("OptionSet", {
      pattern = "diff",
      group = vim.api.nvim_create_augroup("treediff_auto", { clear = true }),
      callback = function()
        if not vim.v.option_new then return end
        vim.schedule(function()
          local diff_wins = {}
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.wo[win].diff then
              table.insert(diff_wins, win)
            end
          end
          if #diff_wins == 2 then
            local lhs = vim.api.nvim_win_get_buf(diff_wins[1])
            local rhs = vim.api.nvim_win_get_buf(diff_wins[2])
            highlight.attach(lhs, rhs)
          end
        end)
      end,
    })
  end
end

--- Diff two strings and return token-level change data.
--- Uses vim.treesitter to parse (consistent with Neovim's own parsers),
--- then sends the syntax trees to Rust for the difftastic diff algorithm.
--- @param old_content string
--- @param new_content string
--- @param lang string  Tree-sitter language name (e.g. "lua", "c_sharp")
--- @return table|nil  { lhs_tokens = {...}, rhs_tokens = {...} }
function M.diff(old_content, new_content, lang)
  local native = load_lib()
  if not native then return nil end

  local tree_walker = require("treediff.tree_walker")

  -- Parse both sides using vim.treesitter
  local lhs_json = tree_walker.parse_to_json(old_content, lang)
  local rhs_json = tree_walker.parse_to_json(new_content, lang)

  if not lhs_json or not rhs_json then
    -- Fallback: try the old direct Rust path
    local ptr = native.treediff_diff_tokens(old_content, new_content, lang)
    if ptr == nil then return nil end
    local json_str = ffi.string(ptr)
    native.treediff_free(ptr)
    local ok, result = pcall(vim.json.decode, json_str)
    if not ok then return nil end
    return result
  end

  -- Send pre-built syntax trees to Rust diff engine
  local ptr = native.treediff_diff_nodes(lhs_json, rhs_json, lang)
  if ptr == nil then return nil end

  local json_str = ffi.string(ptr)
  native.treediff_free(ptr)

  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then return nil end
  return result
end

return M
