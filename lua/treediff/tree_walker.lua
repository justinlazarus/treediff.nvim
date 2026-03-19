-- Walk a Neovim tree-sitter parse tree and convert it to the JSON format
-- expected by the Rust diff engine.
--
-- This replaces the Rust-side tree_sitter_converter.rs. The logic is a
-- faithful port of difftastic's conversion: atom_nodes, delimiter detection,
-- list wrapping for before/after delimiter children, and the flatten
-- optimisation (single-child lists with empty delimiters collapse).

local lang_config = require("treediff.lang_config")

local M = {}

--- Get the byte range of a TSNode: (start_byte, end_byte).
--- Uses the 3rd return value of :start() and :end_() which is the byte offset.
--- @param node userdata  TSNode
--- @return number, number  start_byte (0-indexed), end_byte (0-indexed, exclusive)
local function byte_range(node)
  local _, _, sb = node:start()
  local _, _, eb = node:end_()
  return sb, eb
end

--- Classify an atom node's kind.
--- @param node userdata  TSNode
--- @param content string
--- @return string  "normal"|"comment"|"string"|"error"
local function classify_atom(node, content)
  local kind = node:type()

  -- Error nodes
  if node:has_error() and node:child_count() == 0 then
    return "error"
  end

  -- Extra nodes (comments in most grammars)
  if node:extra() then
    return "comment"
  end
  if kind == "comment" then
    return "comment"
  end

  -- Detect comments by node kind
  if kind:find("comment") then
    return "comment"
  end

  -- Detect strings by node kind
  if kind:find("string")
    or kind == "string_literal"
    or kind == "template_string"
    or kind == "raw_string_literal"
    or kind == "char_literal"
    or kind == "character_literal"
  then
    return "string"
  end

  -- Detect strings by content (quote delimiters)
  if #content >= 2 then
    local first = content:sub(1, 1)
    local last = content:sub(-1, -1)
    if (first == '"' and last == '"')
      or (first == "'" and last == "'")
      or (first == "`" and last == "`")
    then
      return "string"
    end
  end

  -- Detect text content (XML CharData, HTML text)
  if kind == "CharData" or kind == "text" then
    return "string"
  end

  return "normal"
end

--- Build a position array from a TSNode.
--- Returns a list of per-line spans (for multiline nodes).
--- @param node userdata  TSNode
--- @param src_lines string[]
--- @return table[]  list of {line=, start_col=, end_col=} per line
local function node_positions(node, src_lines)
  local sr, sc = node:start()
  local er, ec = node:end_()
  local spans = {}
  for line = sr, er do
    local s = (line == sr) and sc or 0
    local e
    if line == er then
      e = ec
    else
      -- End of this line (byte length)
      local line_text = src_lines[line + 1] or ""
      e = #line_text
    end
    if s ~= e or (sr == er) then
      spans[#spans + 1] = { line = line, start_col = s, end_col = e }
    end
  end
  return spans
end

--- Get the text of a TSNode from source.
--- @param node userdata  TSNode
--- @param src string
--- @return string
local function node_text(node, src)
  local sb, eb = byte_range(node)
  return src:sub(sb + 1, eb)
end

--- Find delimiter positions among children.
--- Returns (open_idx, close_idx) as 0-based child indices, or nil.
--- @param node userdata  TSNode
--- @param src string
--- @param delimiters table  list of {open, close} pairs
--- @return number|nil, number|nil
local function find_delim_positions(node, src, delimiters)
  local count = node:child_count()
  -- Collect child token texts (false for non-token children)
  local tokens = {}  -- 0-indexed to match Rust logic
  for i = 0, count - 1 do
    local child = node:child(i)
    if child:child_count() > 1 or child:extra() then
      tokens[i] = false
    else
      tokens[i] = node_text(child, src)
    end
  end

  for _, pair in ipairs(delimiters) do
    local open_delim, close_delim = pair[1], pair[2]
    for i = 0, count - 1 do
      if tokens[i] == open_delim then
        -- Search for closing delimiter after open
        for j = i + 1, count - 1 do
          if tokens[j] == close_delim then
            return i, j
          end
        end
      end
    end
  end

  return nil, nil
end

--- Forward declaration
local syntax_from_node

--- Create an atom node table from a TSNode.
--- @param node userdata  TSNode
--- @param src string
--- @param src_lines string[]
--- @return table|nil
local function make_atom(node, src, src_lines)
  local content = node_text(node, src)

  -- Skip \n nodes (C/C++ preprocessor artifact)
  if node:type() == "\n" then
    return nil
  end

  -- Trim jsx_text
  if node:type() == "jsx_text" then
    content = content:match("^%s*(.-)%s*$") or content
  end

  local kind = classify_atom(node, content)

  -- Strip trailing \r
  if content:sub(-1) == "\r" then
    content = content:sub(1, -2)
  end

  local positions = node_positions(node, src_lines)

  -- Strip trailing \n (and its position span)
  if content:sub(-1) == "\n" then
    content = content:sub(1, -2)
    if #positions > 1 then
      positions[#positions] = nil
    end
  end

  return { atom = { content = content, kind = kind, pos = positions } }
end

--- Build a list node from a TSNode that has children.
--- Faithful port of difftastic's list_from_cursor.
--- @param node userdata  TSNode
--- @param src string
--- @param src_lines string[]
--- @param config table
--- @return table
local function make_list(node, src, src_lines, config)
  local sr, sc = node:start()
  local er, ec = node:end_()

  local outer_open = ""
  local outer_open_pos = { { line = sr, start_col = sc, end_col = sc } }
  local outer_close = ""
  local outer_close_pos = { { line = er, start_col = ec, end_col = ec } }

  local open_idx, close_idx = find_delim_positions(node, src, config.delimiter_tokens)

  local child_count = node:child_count()
  local i_delim = open_idx or -1
  local j_delim = close_idx or child_count

  local inner_open = outer_open
  local inner_open_pos = { outer_open_pos[1] }
  local inner_close = outer_close
  local inner_close_pos = { outer_close_pos[1] }

  local before_delim = {}
  local between_delim = {}
  local after_delim = {}

  for idx = 0, child_count - 1 do
    local child = node:child(idx)
    if idx < i_delim then
      local result = syntax_from_node(child, src, src_lines, config)
      if result then
        before_delim[#before_delim + 1] = result
      end
    elseif idx == i_delim then
      inner_open = node_text(child, src)
      inner_open_pos = node_positions(child, src_lines)
    elseif idx < j_delim then
      local result = syntax_from_node(child, src, src_lines, config)
      if result then
        between_delim[#between_delim + 1] = result
      end
    elseif idx == j_delim then
      inner_close = node_text(child, src)
      inner_close_pos = node_positions(child, src_lines)
    else
      local result = syntax_from_node(child, src, src_lines, config)
      if result then
        after_delim[#after_delim + 1] = result
      end
    end
  end

  -- Filter out empty atoms from children
  local function filter_empty(children)
    local result = {}
    for _, child in ipairs(children) do
      if child.atom then
        if child.atom.content ~= "" then
          result[#result + 1] = child
        end
      else
        result[#result + 1] = child
      end
    end
    return result
  end

  between_delim = filter_empty(between_delim)

  -- Flatten optimization: single child + empty delimiters -> just the child
  if #between_delim == 1 and inner_open == "" and inner_close == "" then
    if #before_delim == 0 and #after_delim == 0 then
      return between_delim[1]
    end
  end

  local inner_list = {
    list = {
      open = inner_open,
      open_pos = inner_open_pos,
      close = inner_close,
      close_pos = inner_close_pos,
      children = between_delim,
    }
  }

  if #before_delim == 0 and #after_delim == 0 then
    return inner_list
  end

  -- Wrap in outer list
  local all_children = {}
  for _, c in ipairs(before_delim) do all_children[#all_children + 1] = c end
  all_children[#all_children + 1] = inner_list
  for _, c in ipairs(after_delim) do all_children[#all_children + 1] = c end

  return {
    list = {
      open = outer_open,
      open_pos = outer_open_pos,
      close = outer_close,
      close_pos = outer_close_pos,
      children = all_children,
    }
  }
end

--- Convert a single TSNode to a syntax node table.
--- @param node userdata  TSNode
--- @param src string
--- @param src_lines string[]
--- @param config table
--- @return table|nil
function syntax_from_node(node, src, src_lines, config)
  local kind = node:type()

  if config.atom_nodes[kind] then
    return make_atom(node, src, src_lines)
  elseif node:child_count() > 0 then
    return make_list(node, src, src_lines, config)
  else
    return make_atom(node, src, src_lines)
  end
end

--- Ensure the tree-sitter parser for a language is available.
--- Searches runtimepath and packpath for parser .so files.
--- @param lang string
--- @return boolean
local function ensure_parser(lang)
  -- Quick check: try to create a parser directly. If it works, the
  -- language is already registered.
  local ok = pcall(vim.treesitter.get_string_parser, "", lang)
  if ok then return true end

  -- Search via runtime files (covers all rtp entries)
  local paths = vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", true)
  for _, path in ipairs(paths) do
    local ok2 = pcall(vim.treesitter.language.add, lang, { path = path })
    if ok2 then return true end
  end

  -- Search packpath directories for nvim-treesitter parser directories
  -- This catches all plugin managers (lazy, packer, vim-plug, start/, opt/)
  local so_name = lang .. ".so"
  for _, pp in ipairs(vim.opt.packpath:get()) do
    local glob = pp .. "/pack/*/start/nvim-treesitter/parser/" .. so_name
    local found = vim.fn.glob(glob, true, true)
    for _, path in ipairs(found) do
      local ok2 = pcall(vim.treesitter.language.add, lang, { path = path })
      if ok2 then return true end
    end
    glob = pp .. "/pack/*/opt/nvim-treesitter/parser/" .. so_name
    found = vim.fn.glob(glob, true, true)
    for _, path in ipairs(found) do
      local ok2 = pcall(vim.treesitter.language.add, lang, { path = path })
      if ok2 then return true end
    end
  end

  return false
end

--- Parse source code using vim.treesitter and convert to the JSON node
--- format expected by the Rust diff engine.
---
--- @param src string  Source code text
--- @param lang string  Tree-sitter language name (e.g. "lua", "rust", "c_sharp")
--- @return string|nil  JSON string of the node tree, or nil on failure
function M.parse_to_json(src, lang)
  if src:match("^%s*$") then
    return "[]"
  end

  -- Ensure parser is loaded
  if not ensure_parser(lang) then
    return nil
  end

  -- Get or create a parser for this language
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
  if not ok or not parser then
    return nil
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil
  end

  local tree = trees[1]
  local root = tree:root()
  if not root then
    return nil
  end

  local config = lang_config.get(lang)
  local src_lines = vim.split(src, "\n", { plain = true })

  -- Walk root's children (same as Rust: skip the root node itself)
  local nodes = {}
  for i = 0, root:child_count() - 1 do
    local child = root:child(i)
    local result = syntax_from_node(child, src, src_lines, config)
    if result then
      nodes[#nodes + 1] = result
    end
  end

  return vim.json.encode(nodes)
end

return M
