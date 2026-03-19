-- Per-language tree-sitter conversion configs.
-- Ported from difftastic's tree_sitter_converter.rs.
--
-- atom_nodes: node kinds to treat as opaque atoms (ignore children)
-- delimiter_tokens: paired delimiter strings to identify List boundaries

local M = {}

-- Common OCaml atom nodes shared between OCaml and OCaml Interface.
local OCAML_ATOM_NODES = {
  "character", "string", "quoted_string", "tag",
  "type_variable", "attribute_id",
}

local function set(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

local configs = {
  ada = {
    atom_nodes = set({"string_literal", "character_literal"}),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}},
  },
  apex = {
    atom_nodes = set({"string_literal", "null_literal", "boolean", "int",
      "decimal_floating_point_literal", "date_literal", "currency_literal"}),
    delimiter_tokens = {{"[", "]"}, {"(", ")"}, {"{", "}"}},
  },
  bash = {
    atom_nodes = set({"string", "raw_string", "heredoc_body", "simple_expansion"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}},
  },
  c = {
    atom_nodes = set({"string_literal", "char_literal"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}},
  },
  cpp = {
    atom_nodes = set({"string_literal", "char_literal"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}, {"<", ">"}},
  },
  clojure = {
    atom_nodes = set({"kwd_lit", "regex_lit"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  cmake = {
    atom_nodes = set({"argument"}),
    delimiter_tokens = {{"(", ")"}},
  },
  commonlisp = {
    atom_nodes = set({"str_lit", "char_lit"}),
    delimiter_tokens = {{"(", ")"}},
  },
  c_sharp = {
    atom_nodes = set({"string_literal", "verbatim_string_literal", "character_literal", "modifier"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}},
  },
  css = {
    atom_nodes = set({"integer_value", "float_value", "color_value", "string_value"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}},
  },
  dart = {
    atom_nodes = set({"string_literal", "script_tag"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"<", ">"}},
  },
  devicetree = {
    atom_nodes = set({"byte_string_literal", "string_literal"}),
    delimiter_tokens = {{"<", ">"}, {"{", "}"}, {"(", ")"}},
  },
  elixir = {
    atom_nodes = set({"string", "sigil", "heredoc"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"do", "end"}},
  },
  elm = {
    atom_nodes = set({"string_constant_expr"}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}, {"(", ")"}},
  },
  elvish = {
    atom_nodes = set({}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"|", "|"}},
  },
  elisp = {
    atom_nodes = set({}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  erlang = {
    atom_nodes = set({}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}},
  },
  fsharp = {
    atom_nodes = set({"string", "triple_quoted_string"}),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"{", "}"}},
  },
  fortran = {
    atom_nodes = set({"string_literal"}),
    delimiter_tokens = {{"(", ")"}, {"(/", "/)"}, {"[", "]"}},
  },
  gleam = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"{", "}"}},
  },
  go = {
    atom_nodes = set({"interpreted_string_literal", "raw_string_literal"}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}, {"(", ")"}},
  },
  hack = {
    atom_nodes = set({"prefixed_string", "heredoc"}),
    delimiter_tokens = {{"[", "]"}, {"(", ")"}, {"<", ">"}, {"{", "}"}},
  },
  hare = {
    atom_nodes = set({"string_constant", "rune_constant"}),
    delimiter_tokens = {{"[", "]"}, {"(", ")"}, {"{", "}"}},
  },
  haskell = {
    atom_nodes = set({"qualified_variable", "qualified_module", "qualified_constructor", "strict_type"}),
    delimiter_tokens = {{"[", "]"}, {"(", ")"}},
  },
  hcl = {
    atom_nodes = set({"string_lit", "heredoc_template"}),
    delimiter_tokens = {{"[", "]"}, {"(", ")"}, {"{", "}"}, {"%{", "}"}, {"%{~", "~}"}, {"${", "}"}},
  },
  html = {
    atom_nodes = set({"doctype", "quoted_attribute_value", "raw_text", "tag_name", "text"}),
    delimiter_tokens = {{"<", ">"}, {"<!", ">"}, {"<!--", "-->"}},
  },
  janet = {
    atom_nodes = set({}),
    delimiter_tokens = {{"@{", "}"}, {"@(", ")"}, {"@[", "]"}, {"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  java = {
    atom_nodes = set({"string_literal", "boolean_type", "integral_type", "floating_point_type", "void_type"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}},
  },
  javascript = {
    atom_nodes = set({"string", "template_string", "regex"}),
    delimiter_tokens = {{"[", "]"}, {"(", ")"}, {"{", "}"}, {"<", ">"}},
  },
  json = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}},
  },
  julia = {
    atom_nodes = set({"string_literal", "prefixed_string_literal", "command_literal", "character_literal"}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}, {"(", ")"}},
  },
  kotlin = {
    atom_nodes = set({"nullable_type", "string_literal", "line_string_literal", "character_literal"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}, {"<", ">"}},
  },
  latex = {
    atom_nodes = set({}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}},
  },
  lua = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}},
  },
  make = {
    atom_nodes = set({"shell_text", "text"}),
    delimiter_tokens = {{"(", ")"}},
  },
  newick = {
    atom_nodes = set({}),
    delimiter_tokens = {{"(", ")"}},
  },
  nix = {
    atom_nodes = set({"string_expression", "indented_string_expression"}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}},
  },
  objc = {
    atom_nodes = set({"string_literal"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}, {"@(", ")"}, {"@{", "}"}, {"@[", "]"}},
  },
  ocaml = {
    atom_nodes = set(OCAML_ATOM_NODES),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"{", "}"}},
  },
  ocaml_interface = {
    atom_nodes = set(OCAML_ATOM_NODES),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"{", "}"}},
  },
  pascal = {
    atom_nodes = set({}),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}},
  },
  perl = {
    atom_nodes = set({"string_single_quoted", "string_double_quoted", "comments",
      "command_qx_quoted", "pattern_matcher_m", "regex_pattern_qr",
      "transliteration_tr_or_y", "substitution_pattern_s",
      "scalar_variable", "array_variable", "hash_variable", "hash_access_variable"}),
    delimiter_tokens = {{"(", ")"}, {"{", "}"}, {"[", "]"}},
  },
  php = {
    atom_nodes = set({"string", "encapsed_string"}),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"{", "}"}},
  },
  proto = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {{"{", "}"}},
  },
  python = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"{", "}"}},
  },
  qml = {
    atom_nodes = set({"string", "template_string", "regex"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"<", ">"}},
  },
  r = {
    atom_nodes = set({"string", "special"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  racket = {
    atom_nodes = set({"string", "byte_string", "regex", "here_string"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  ruby = {
    atom_nodes = set({"string", "heredoc_body", "regex"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"|", "|"},
      {"def", "end"}, {"begin", "end"}, {"class", "end"}},
  },
  rust = {
    atom_nodes = set({"char_literal", "string_literal", "raw_string_literal"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"|", "|"}, {"<", ">"}},
  },
  scala = {
    atom_nodes = set({"string", "template_string", "interpolated_string_expression"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  scheme = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  scss = {
    atom_nodes = set({"integer_value", "float_value", "color_value"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}},
  },
  smali = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {},
  },
  solidity = {
    atom_nodes = set({"string", "hex_string_literal", "unicode_string_literal"}),
    delimiter_tokens = {{"[", "]"}, {"(", ")"}, {"{", "}"}},
  },
  sql = {
    atom_nodes = set({"string", "identifier"}),
    delimiter_tokens = {{"(", ")"}},
  },
  swift = {
    atom_nodes = set({"line_string_literal"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"<", ">"}},
  },
  toml = {
    atom_nodes = set({"string", "quoted_key"}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}},
  },
  tsx = {
    atom_nodes = set({"string", "template_string"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"<", ">"}},
  },
  typescript = {
    atom_nodes = set({"string", "template_string", "regex", "predefined_type"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}, {"<", ">"}},
  },
  xml = {
    atom_nodes = set({"AttValue", "XMLDecl"}),
    delimiter_tokens = {{"<", ">"}},
  },
  yaml = {
    atom_nodes = set({"string_scalar", "double_quote_scalar", "single_quote_scalar", "block_scalar"}),
    delimiter_tokens = {{"{", "}"}, {"(", ")"}, {"[", "]"}},
  },
  verilog = {
    atom_nodes = set({"integral_number"}),
    delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"begin", "end"}},
  },
  vhdl = {
    atom_nodes = set({}),
    delimiter_tokens = {{"(", ")"}},
  },
  zig = {
    atom_nodes = set({"string"}),
    delimiter_tokens = {{"{", "}"}, {"[", "]"}, {"(", ")"}},
  },
}

-- Aliases
configs.c_plus_plus = configs.cpp
configs.common_lisp = configs.commonlisp
configs.f_sharp = configs.fsharp
configs.emacs_lisp = configs.elisp
configs.janet_simple = configs.janet
configs.jsx = configs.javascript
configs.objective_c = configs.objc
configs.protobuf = configs.proto

local default_config = {
  atom_nodes = set({}),
  delimiter_tokens = {{"(", ")"}, {"[", "]"}, {"{", "}"}},
}

function M.get(lang_name)
  return configs[lang_name] or default_config
end

return M
