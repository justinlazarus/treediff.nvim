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

  -- Platform-specific binary names
  local sysname = vim.uv.os_uname().sysname
  local machine = vim.uv.os_uname().machine
  local names = { "treediff_native.so" } -- default (macOS arm64)
  if sysname == "Linux" then
    names = { "treediff_native_linux.so", "treediff_native.so" }
  elseif sysname == "Darwin" and (machine == "x86_64" or machine == "i386") then
    names = { "treediff_native_x86.so", "treediff_native.so" }
  end

  -- Find the native lib by searching runtimepath
  local candidates = {}
  for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
    for _, name in ipairs(names) do
      table.insert(candidates, rtp .. "/lib/" .. name)
    end
    table.insert(candidates, rtp .. "/target/release/libtreediff.dylib")
    table.insert(candidates, rtp .. "/target/release/libtreediff.so")
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
    -- Track state for restoring on diffoff
    local saved_hl = nil

    local function apply_diff_style(diff_wins)
      -- Save and neutralize built-in diff highlights
      if not saved_hl then
        saved_hl = {
          DiffText = vim.api.nvim_get_hl(0, { name = "DiffText" }),
          DiffChange = vim.api.nvim_get_hl(0, { name = "DiffChange" }),
          DiffAdd = vim.api.nvim_get_hl(0, { name = "DiffAdd" }),
          DiffDelete = vim.api.nvim_get_hl(0, { name = "DiffDelete" }),
        }
      end

      -- Check if tree-sitter parser exists for the filetype
      local lhs_buf = vim.api.nvim_win_get_buf(diff_wins[1])
      local rhs_buf = vim.api.nvim_win_get_buf(diff_wins[2])
      local ft = vim.bo[lhs_buf].filetype
      local ft_map_mod = require("treediff.ft_map")
      local ts_lang = ft_map_mod[ft] or ft
      local has_ts = pcall(vim.treesitter.language.inspect, ts_lang)

      if has_ts and ft ~= "" then
        -- Tree-aware alignment: disable Neovim's diff mode, use our own pipeline
        vim.cmd("diffoff!")
        vim.api.nvim_set_hl(0, "DiffChange", {})
        vim.api.nvim_set_hl(0, "DiffAdd", {})
        vim.api.nvim_set_hl(0, "DiffText", {})
        vim.api.nvim_set_hl(0, "DiffDelete", {})
        M.view(lhs_buf, rhs_buf)
      else
        -- Fallback: overlay token highlights on Neovim's diff mode
        vim.api.nvim_set_hl(0, "DiffChange", {})
        vim.api.nvim_set_hl(0, "DiffAdd", {})
        vim.api.nvim_set_hl(0, "DiffText", {})
        vim.api.nvim_set_hl(0, "DiffDelete", {})

        vim.api.nvim_set_hl(0, "TreeDiffDelete", { fg = "#ff6e6e", bold = true })
        vim.api.nvim_set_hl(0, "TreeDiffAdd", { fg = "#6eff6e", bold = true })
        vim.api.nvim_set_hl(0, "TreeDiffDeleteNr", { fg = "#ff6e6e", bold = true })
        vim.api.nvim_set_hl(0, "TreeDiffAddNr", { fg = "#6eff6e", bold = true })

        vim.opt.fillchars:append("diff: ")
        highlight.attach(lhs_buf, rhs_buf)

        for _, win in ipairs(diff_wins) do
          local buf = vim.api.nvim_win_get_buf(win)
          pcall(vim.treesitter.stop, buf)
          vim.bo[buf].syntax = ""
        end
      end
    end

    local function restore_diff_style()
      if saved_hl then
        for name, hl in pairs(saved_hl) do
          vim.api.nvim_set_hl(0, name, hl)
        end
        saved_hl = nil
      end
      -- Only clear buffers that don't have treediff alignment state
      -- (Plz manages its own treediff buffers via _line_nums)
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if not vim.b[buf].treediff_buf_to_file then
          highlight.clear(buf)
          pcall(function()
            vim.wo[win].scrollbind = false
            vim.wo[win].cursorbind = false
            vim.wo[win].statuscolumn = ""
          end)
        end
      end
    end

    vim.api.nvim_create_autocmd("OptionSet", {
      pattern = "diff",
      group = vim.api.nvim_create_augroup("treediff_auto", { clear = true }),
      callback = function()
        vim.schedule(function()
          local diff_wins = {}
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.wo[win].diff then
              table.insert(diff_wins, win)
            end
          end
          if #diff_wins >= 2 then
            apply_diff_style(diff_wins)
          else
            restore_diff_style()
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

--- Full pipeline: diff → align → render two buffers side by side.
--- @param lhs_buf number  buffer with original content
--- @param rhs_buf number  buffer with new content
function M.view(lhs_buf, rhs_buf)
  local align = require("treediff.align")
  local render = require("treediff.render")
  local ft_map = require("treediff.ft_map")

  local ft = vim.bo[lhs_buf].filetype
  local lang = ft_map[ft] or ft

  local lhs_lines = vim.api.nvim_buf_get_lines(lhs_buf, 0, -1, false)
  local rhs_lines = vim.api.nvim_buf_get_lines(rhs_buf, 0, -1, false)
  local lhs_text = table.concat(lhs_lines, "\n") .. "\n"
  local rhs_text = table.concat(rhs_lines, "\n") .. "\n"

  -- Run structural diff (returns tokens + anchors)
  local result = M.diff(lhs_text, rhs_text, lang)
  if not result then return end

  -- Build aligned padded arrays
  local aligned = align.build(lhs_lines, rhs_lines, result.anchors)

  -- Build coordinate translation maps
  local lhs_maps = align.build_maps(aligned.lhs_padded)
  local rhs_maps = align.build_maps(aligned.rhs_padded)

  -- Find the windows showing these buffers
  local lhs_win, rhs_win
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == lhs_buf then lhs_win = win
    elseif buf == rhs_buf then rhs_win = win
    end
  end
  if not lhs_win or not rhs_win then return end

  -- Render
  render.render(lhs_win, rhs_win, aligned.lhs_padded, aligned.rhs_padded, result, lhs_maps, rhs_maps)
end

--- Return the buf_to_file line mapping for a buffer rendered by M.view().
--- @param bufnr number
--- @return table|nil  { [1-indexed_buf_row] = 0-indexed_file_line }
function M.line_map(bufnr)
  return vim.b[bufnr].treediff_buf_to_file
end

--- Re-run the diff + align + render pipeline for two buffers.
--- @param lhs_buf number
--- @param rhs_buf number
function M.recompute(lhs_buf, rhs_buf)
  M.view(lhs_buf, rhs_buf)
end

return M
