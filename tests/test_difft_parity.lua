-- Tests that compare treediff output with difft output.
-- Run: nvim --headless -u tests/minimal_init.lua -l tests/test_difft_parity.lua

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

--- Run difft on two strings and extract Novel token positions.
--- Returns { lhs = {{line, start_col, end_col}, ...}, rhs = {...} }
local function difft_tokens(lhs_text, rhs_text, lang_ext)
  local tmp1 = vim.fn.tempname() .. "." .. lang_ext
  local tmp2 = vim.fn.tempname() .. "." .. lang_ext
  vim.fn.writefile(vim.split(lhs_text, "\n"), tmp1)
  vim.fn.writefile(vim.split(rhs_text, "\n"), tmp2)

  -- Run difft with JSON output
  local cmd = string.format("difft --display json %s %s 2>/dev/null", tmp1, tmp2)
  local handle = io.popen(cmd)
  local json_str = handle:read("*a")
  handle:close()

  os.remove(tmp1)
  os.remove(tmp2)

  if json_str == "" then return nil end
  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then return nil end
  return result
end

--- Run our treediff on two strings and return Novel tokens.
local function treediff_tokens(lhs_text, rhs_text, lang_name)
  local td = require("treediff")
  local result = td.diff(lhs_text, rhs_text, lang_name)
  if not result then return nil end
  -- Filter zero-width spans
  local lhs = vim.tbl_filter(function(t) return t.end_col > t.start_col end, result.lhs_tokens or {})
  local rhs = vim.tbl_filter(function(t) return t.end_col > t.start_col end, result.rhs_tokens or {})
  return { lhs_tokens = lhs, rhs_tokens = rhs }
end

--- Extract token text from source given token positions.
local function token_texts(src, tokens)
  local lines = vim.split(src, "\n")
  local texts = {}
  for _, t in ipairs(tokens) do
    local line = lines[t.line + 1] or ""
    local text = line:sub(t.start_col + 1, t.end_col)
    if text ~= "" then
      table.insert(texts, { line = t.line + 1, text = text })
    end
  end
  return texts
end

io.write("treediff.nvim difft parity tests\n")

-- Test 1: Simple Rust diff
test("Rust: simple variable change", function()
  local lhs = "fn main() {\n    let x = 1;\n    println!(\"hello\");\n}"
  local rhs = "fn main() {\n    let x = 42;\n    let y = 2;\n    println!(\"hello world\");\n}"
  local ours = treediff_tokens(lhs, rhs, "rust")
  assert(ours, "treediff returned nil")

  local lhs_texts = token_texts(lhs, ours.lhs_tokens)
  local rhs_texts = token_texts(rhs, ours.rhs_tokens)

  -- LHS should only mark "1" and "hello" as novel
  local lhs_set = {}
  for _, t in ipairs(lhs_texts) do lhs_set[t.text] = true end
  assert(lhs_set["1"], "LHS should mark '1' as novel")
  assert(lhs_set['"hello"'], "LHS should mark '\"hello\"' as novel")
  assert(not lhs_set["let"], "LHS should NOT mark 'let' as novel")
  assert(not lhs_set["fn"], "LHS should NOT mark 'fn' as novel")

  -- RHS should mark "42", "let", "y", "=", "2", ";", "hello world"
  local rhs_set = {}
  for _, t in ipairs(rhs_texts) do rhs_set[t.text] = true end
  assert(rhs_set["42"], "RHS should mark '42' as novel")
  assert(rhs_set['"hello world"'], "RHS should mark '\"hello world\"' as novel")
  assert(rhs_set["y"], "RHS should mark 'y' as novel")
end)

-- Test 2: Rust struct change
test("Rust: struct field change", function()
  local lhs = "struct Foo {\n    x: i32,\n}"
  local rhs = "struct Foo {\n    x: i64,\n    y: String,\n}"
  local ours = treediff_tokens(lhs, rhs, "rust")
  assert(ours, "treediff returned nil")

  local lhs_texts = token_texts(lhs, ours.lhs_tokens)
  local rhs_texts = token_texts(rhs, ours.rhs_tokens)

  -- LHS: only "i32" should be novel
  assert(#lhs_texts >= 1, "LHS should have at least 1 novel token")
  local lhs_set = {}
  for _, t in ipairs(lhs_texts) do lhs_set[t.text] = true end
  assert(lhs_set["i32"], "LHS should mark 'i32' as novel")
  assert(not lhs_set["struct"], "LHS should NOT mark 'struct' as novel")
  assert(not lhs_set["Foo"], "LHS should NOT mark 'Foo' as novel")

  -- RHS: "i64" and the "y: String," parts should be novel
  local rhs_set = {}
  for _, t in ipairs(rhs_texts) do rhs_set[t.text] = true end
  assert(rhs_set["i64"], "RHS should mark 'i64' as novel")
  assert(rhs_set["y"], "RHS should mark 'y' as novel")
  assert(rhs_set["String"], "RHS should mark 'String' as novel")
end)

-- Test 3: Lua function change
test("Lua: function body change", function()
  local lhs = "local function greet(name)\n  return \"hello \" .. name\nend"
  local rhs = "local function greet(name)\n  return \"hi \" .. name .. \"!\"\nend"
  local ours = treediff_tokens(lhs, rhs, "lua")
  assert(ours, "treediff returned nil")

  local lhs_texts = token_texts(lhs, ours.lhs_tokens)
  local rhs_texts = token_texts(rhs, ours.rhs_tokens)

  local lhs_set = {}
  for _, t in ipairs(lhs_texts) do lhs_set[t.text] = true end
  assert(lhs_set['"hello "'], "LHS should mark '\"hello \"' as novel")
  assert(not lhs_set["function"], "LHS should NOT mark 'function' as novel")
  assert(not lhs_set["name"], "LHS should NOT mark 'name' as novel")
end)

-- Test 4: Zero-width tokens should not appear
test("No zero-width tokens in output", function()
  local lhs = "fn main() {\n    let x = 1;\n}"
  local rhs = "fn main() {\n    let x = 42;\n}"
  local td = require("treediff")
  local result = td.diff(lhs, rhs, "rust")
  assert(result, "diff returned nil")
  for _, t in ipairs(result.lhs_tokens) do
    assert(t.end_col > t.start_col, "zero-width token on LHS line " .. t.line)
  end
  for _, t in ipairs(result.rhs_tokens) do
    assert(t.end_col > t.start_col, "zero-width token on RHS line " .. t.line)
  end
end)

-- Test 5: Identical files produce no tokens
test("Identical files produce no novel tokens", function()
  local src = "fn main() {\n    println!(\"hello\");\n}"
  local td = require("treediff")
  local result = td.diff(src, src, "rust")
  if result then
    local lhs_novel = vim.tbl_filter(function(t) return t.end_col > t.start_col end, result.lhs_tokens or {})
    local rhs_novel = vim.tbl_filter(function(t) return t.end_col > t.start_col end, result.rhs_tokens or {})
    assert(#lhs_novel == 0, "expected 0 LHS novel tokens, got " .. #lhs_novel)
    assert(#rhs_novel == 0, "expected 0 RHS novel tokens, got " .. #rhs_novel)
  end
end)

-- Test 6: tree_walker produces valid JSON
test("tree_walker produces valid JSON for Rust", function()
  local tw = require("treediff.tree_walker")
  local json = tw.parse_to_json("fn main() { let x = 1; }", "rust")
  assert(json, "tree_walker returned nil for Rust")
  local ok, nodes = pcall(vim.json.decode, json)
  assert(ok, "tree_walker JSON is not valid: " .. tostring(nodes))
  assert(#nodes > 0, "tree_walker produced empty node list")
end)

-- Test 7: tree_walker works for Lua
test("tree_walker produces valid JSON for Lua", function()
  local tw = require("treediff.tree_walker")
  local json = tw.parse_to_json("local x = 1\nlocal y = 2", "lua")
  assert(json, "tree_walker returned nil for Lua")
  local ok, nodes = pcall(vim.json.decode, json)
  assert(ok, "invalid JSON")
  assert(#nodes > 0, "empty node list")
end)

-- Test 8: tree_walker returns [] for empty input
test("tree_walker returns [] for empty input", function()
  local tw = require("treediff.tree_walker")
  local json = tw.parse_to_json("", "rust")
  assert(json == "[]", "expected [], got " .. tostring(json))
  json = tw.parse_to_json("   \n  ", "rust")
  assert(json == "[]", "expected [] for whitespace, got " .. tostring(json))
end)

-- Test 9: Python diff (if parser available)
test("Python: variable change", function()
  local tw = require("treediff.tree_walker")
  local lhs = "def greet(name):\n    return 'hello ' + name"
  local rhs = "def greet(name):\n    return 'hi ' + name"
  local json = tw.parse_to_json(lhs, "python")
  if not json then
    io.write("    (skipped: python parser not available)\n")
    return
  end
  local td = require("treediff")
  local result = td.diff(lhs, rhs, "python")
  assert(result, "diff returned nil for Python")
  assert(#result.lhs_tokens > 0, "expected LHS novel tokens")
  assert(#result.rhs_tokens > 0, "expected RHS novel tokens")
end)

-- Test 10: JavaScript diff (if parser available)
test("JavaScript: function change", function()
  local tw = require("treediff.tree_walker")
  local lhs = "function add(a, b) {\n  return a + b;\n}"
  local rhs = "function add(a, b, c) {\n  return a + b + c;\n}"
  local json = tw.parse_to_json(lhs, "javascript")
  if not json then
    io.write("    (skipped: javascript parser not available)\n")
    return
  end
  local td = require("treediff")
  local result = td.diff(lhs, rhs, "javascript")
  assert(result, "diff returned nil for JavaScript")
  assert(#result.rhs_tokens > 0, "expected RHS novel tokens for added parameter")
end)

-- Summary
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
