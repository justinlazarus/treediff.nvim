local M = {}
local ffi = require("ffi")

pcall(ffi.cdef, [[
  int treediff_diff_files(const char *old_path, const char *new_path, const char *out_path);
  char *treediff_diff_tokens(const char *old_src, const char *new_src, const char *lang_name);
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

--- Set up treediff as the diffexpr.
function M.setup()
  local native = load_lib()
  if not native then return end

  M._native = native
  vim.o.diffexpr = "v:lua.TreeDiffExpr()"

  _G.TreeDiffExpr = function()
    local old_file = vim.v.fname_in
    local new_file = vim.v.fname_new
    local out_file = vim.v.fname_out
    native.treediff_diff_files(old_file, new_file, out_file)
  end
end

--- Diff two strings and return token-level change data.
--- @param old_content string
--- @param new_content string
--- @param lang string  Tree-sitter language name (e.g. "lua", "c_sharp")
--- @return table|nil  { lhs_tokens = {...}, rhs_tokens = {...} }
function M.diff(old_content, new_content, lang)
  local native = load_lib()
  if not native then return nil end

  local ptr = native.treediff_diff_tokens(old_content, new_content, lang)
  if ptr == nil then return nil end

  local json_str = ffi.string(ptr)
  native.treediff_free(ptr)

  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then return nil end
  return result
end

return M
