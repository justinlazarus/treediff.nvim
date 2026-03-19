-- Headless Neovim tests for treediff.nvim
-- Run: nvim --headless -u tests/minimal_init.lua -l tests/test_diffview.lua

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write("  PASS: " .. name .. "\n")
  else
    failed = failed + 1
    io.write("  FAIL: " .. name .. " — " .. tostring(err) .. "\n")
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "") .. " expected " .. vim.inspect(a) .. " == " .. vim.inspect(b))
  end
end

io.write("treediff.nvim tests\n")

-- 1. Library loads
test("library loads", function()
  local td = require("treediff")
  assert(td._native, "native library not loaded")
end)

-- 2. diff() returns token data for known inputs
test("diff returns tokens", function()
  local td = require("treediff")
  local result = td.diff("fn main() {}", "fn main() { 1 }", "rust")
  assert(result, "diff returned nil")
  assert(result.lhs_tokens, "missing lhs_tokens")
  assert(result.rhs_tokens, "missing rhs_tokens")
  assert(#result.rhs_tokens > 0, "expected rhs tokens for added code")
end)

-- 3. Token positions are 0-indexed numbers
test("token positions are numbers", function()
  local td = require("treediff")
  local result = td.diff("let x = 1;", "let x = 2;", "rust")
  assert(result and #result.rhs_tokens > 0, "no tokens")
  local tok = result.rhs_tokens[1]
  assert(type(tok.line) == "number", "line not a number")
  assert(type(tok.start_col) == "number", "start_col not a number")
  assert(type(tok.end_col) == "number", "end_col not a number")
end)

-- 4. ft_map has expected entries
test("ft_map has entries", function()
  local ft_map = require("treediff.ft_map")
  assert_eq(ft_map.cs, "c_sharp")
  assert_eq(ft_map.rust, "rust")
  assert_eq(ft_map.python, "python")
end)

-- 5. highlight module loads
test("highlight module loads", function()
  local hl = require("treediff.highlight")
  assert(hl.apply, "missing apply")
  assert(hl.attach, "missing attach")
  assert(hl.clear, "missing clear")
  assert(hl.namespace, "missing namespace")
end)

-- 6. :TreeDiff opens two windows in diff mode
test("TreeDiff command opens diff", function()
  -- Create two temp files
  local tmp1 = vim.fn.tempname() .. ".rs"
  local tmp2 = vim.fn.tempname() .. ".rs"
  vim.fn.writefile({ "fn main() {}" }, tmp1)
  vim.fn.writefile({ "fn main() { 1 }" }, tmp2)

  vim.cmd("TreeDiff " .. tmp1 .. " " .. tmp2)
  -- Process scheduled callbacks
  vim.wait(100, function() return false end)

  local wins = vim.api.nvim_tabpage_list_wins(0)
  assert(#wins >= 2, "expected 2 windows, got " .. #wins)

  local diff_count = 0
  for _, win in ipairs(wins) do
    if vim.wo[win].diff then
      diff_count = diff_count + 1
    end
  end
  assert_eq(diff_count, 2, "diff windows")

  -- Cleanup
  vim.cmd("TreeDiffOff")
  vim.cmd("only")
  os.remove(tmp1)
  os.remove(tmp2)
end)

-- 7. Extmarks are placed after TreeDiff
test("extmarks placed after TreeDiff", function()
  local hl = require("treediff.highlight")
  local ns = hl.namespace()

  local tmp1 = vim.fn.tempname() .. ".rs"
  local tmp2 = vim.fn.tempname() .. ".rs"
  vim.fn.writefile({ "fn main() {}" }, tmp1)
  vim.fn.writefile({ "fn main() { 1 }" }, tmp2)

  vim.cmd("TreeDiff " .. tmp1 .. " " .. tmp2)
  vim.wait(200, function() return false end)

  -- Check extmarks exist in at least one buffer
  local found = false
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    if #marks > 0 then
      found = true
      break
    end
  end
  assert(found, "no extmarks found in treediff namespace")

  vim.cmd("TreeDiffOff")
  vim.cmd("only")
  os.remove(tmp1)
  os.remove(tmp2)
end)

-- 8. TreeDiffOff removes extmarks
test("TreeDiffOff clears extmarks", function()
  local hl = require("treediff.highlight")
  local ns = hl.namespace()

  local tmp1 = vim.fn.tempname() .. ".rs"
  local tmp2 = vim.fn.tempname() .. ".rs"
  vim.fn.writefile({ "let x = 1;" }, tmp1)
  vim.fn.writefile({ "let x = 2;" }, tmp2)

  vim.cmd("TreeDiff " .. tmp1 .. " " .. tmp2)
  vim.wait(200, function() return false end)
  vim.cmd("TreeDiffOff")

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert_eq(#marks, 0, "extmarks remain after TreeDiffOff")
  end

  vim.cmd("only")
  os.remove(tmp1)
  os.remove(tmp2)
end)

-- Summary
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
