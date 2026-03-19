local M = {}
local highlight = require("treediff.highlight")

-- Save/restore Neovim's built-in DiffText so we can neutralize it during our view.
local saved_difftext = nil

--- Open two files in Neovim's diff mode with token-level highlights.
--- @param file1 string
--- @param file2 string
function M.open(file1, file2)
  -- Save highlights and fillchars for restoration on close.
  M._saved_hl = {
    DiffText = vim.api.nvim_get_hl(0, { name = "DiffText" }),
    DiffChange = vim.api.nvim_get_hl(0, { name = "DiffChange" }),
    DiffAdd = vim.api.nvim_get_hl(0, { name = "DiffAdd" }),
    DiffDelete = vim.api.nvim_get_hl(0, { name = "DiffDelete" }),
  }
  M._saved_fillchars = vim.o.fillchars
  vim.opt.fillchars:append("diff: ")

  vim.cmd("edit " .. vim.fn.fnameescape(file1))
  vim.cmd("diffthis")
  local lhs_bufnr = vim.api.nvim_get_current_buf()

  vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(file2))
  local rhs_bufnr = vim.api.nvim_get_current_buf()

  -- Apply all overrides in vim.schedule so they run AFTER all autocommands
  -- (colorscheme, filetype, syntax) triggered by loading the files.
  vim.schedule(function()
    -- Difftastic style: bold red/green text only, no background highlights.
    -- Neutralize ALL built-in diff highlights.
    vim.api.nvim_set_hl(0, "DiffChange", {})
    vim.api.nvim_set_hl(0, "DiffAdd", {})
    vim.api.nvim_set_hl(0, "DiffText", {})
    vim.api.nvim_set_hl(0, "DiffDelete", {})

    -- Token highlights: bold red (deleted), bold green (added)
    vim.api.nvim_set_hl(0, "TreeDiffDelete", { fg = "#ff6e6e", bold = true })
    vim.api.nvim_set_hl(0, "TreeDiffAdd", { fg = "#6eff6e", bold = true })
    vim.api.nvim_set_hl(0, "TreeDiffDeleteNr", { fg = "#ff6e6e", bold = true })
    vim.api.nvim_set_hl(0, "TreeDiffAddNr", { fg = "#6eff6e", bold = true })

    -- Cursorline: background only, no underline.
    -- Use a private highlight + per-window winhl to avoid colorscheme overrides.
    M._saved_hl.CursorLine = vim.api.nvim_get_hl(0, { name = "CursorLine" })
    vim.api.nvim_set_hl(0, "TreeDiffCursorLine", { bg = "#313244", underline = false, undercurl = false, underdashed = false, underdotted = false, strikethrough = false })

    -- Apply token highlights BEFORE stripping filetype (highlight needs it)
    highlight.attach(lhs_bufnr, rhs_bufnr)

    -- Now make diff buffers completely plain — no plugins should decorate these.
    -- Stripping filetype + syntax signals to virtually all plugins
    -- (indent guides, linters, formatters, LSP, etc.) to leave the buffer alone.
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)

      -- Kill all syntax/highlighting engines
      pcall(vim.treesitter.stop, buf)
      vim.bo[buf].syntax = ""
      vim.bo[buf].filetype = ""

      -- Window options: cursorline on, nothing else
      vim.wo[win].cursorline = true
      vim.wo[win].winhighlight = "CursorLine:TreeDiffCursorLine,CursorLineNr:TreeDiffCursorLine"
      vim.wo[win].signcolumn = "no"
      vim.wo[win].foldcolumn = "0"
      vim.wo[win].colorcolumn = ""
      vim.wo[win].statuscolumn = ""
      vim.wo[win].spell = false
      vim.wo[win].list = false
      vim.wo[win].number = true
      vim.wo[win].relativenumber = false
    end
  end)
end

--- Close diff mode and clear highlights in all windows of the current tab.
function M.close()
  vim.cmd("diffoff!")
  pcall(vim.api.nvim_del_augroup_by_name, "treediff_highlight")
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    highlight.clear(vim.api.nvim_win_get_buf(win))
  end
  -- Restore original highlights
  if M._saved_hl then
    for name, hl in pairs(M._saved_hl) do
      vim.api.nvim_set_hl(0, name, hl)
    end
    M._saved_hl = nil
  end
  if M._saved_fillchars then
    vim.o.fillchars = M._saved_fillchars
    M._saved_fillchars = nil
  end
end

--- Open a demo diff with sample code.
--- @param lang? string  "rust" (default) or "cs"
function M.test(lang)
  lang = lang or "rust"
  local lhs, rhs, ext
  if lang == "cs" then
    ext = ".cs"
    lhs = {
      "using System;",
      "using System.Collections.Generic;",
      "",
      "namespace OrderSystem",
      "{",
      "    public class Order",
      "    {",
      "        public int Id { get; set; }",
      "        public string CustomerName { get; set; }",
      "        public List<OrderItem> Items { get; set; } = new List<OrderItem>();",
      "        public DateTime CreatedAt { get; set; } = DateTime.Now;",
      "",
      "        public decimal GetTotal()",
      "        {",
      "            decimal total = 0;",
      "            foreach (var item in Items)",
      "            {",
      "                total += item.Price * item.Quantity;",
      "            }",
      "            return total;",
      "        }",
      "",
      "        public void AddItem(string name, decimal price, int qty)",
      "        {",
      "            Items.Add(new OrderItem { Name = name, Price = price, Quantity = qty });",
      "        }",
      "",
      "        public override string ToString()",
      "        {",
      '            return $"Order #{Id} for {CustomerName}: {GetTotal():C}";',
      "        }",
      "    }",
      "",
      "    public class OrderItem",
      "    {",
      "        public string Name { get; set; }",
      "        public decimal Price { get; set; }",
      "        public int Quantity { get; set; }",
      "    }",
      "}",
    }
    rhs = {
      "using System;",
      "using System.Collections.Generic;",
      "using System.Linq;",
      "",
      "namespace OrderSystem",
      "{",
      "    public enum OrderStatus { Pending, Confirmed, Shipped, Cancelled }",
      "",
      "    public class Order",
      "    {",
      "        public int Id { get; set; }",
      "        public string CustomerName { get; set; }",
      "        public string CustomerEmail { get; set; }",
      "        public List<OrderItem> Items { get; set; } = new List<OrderItem>();",
      "        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;",
      "        public OrderStatus Status { get; set; } = OrderStatus.Pending;",
      "",
      "        public decimal GetTotal(bool includeTax = false)",
      "        {",
      "            var subtotal = Items.Sum(i => i.Price * i.Quantity);",
      "            return includeTax ? subtotal * 1.08m : subtotal;",
      "        }",
      "",
      "        public void AddItem(string name, decimal price, int qty)",
      "        {",
      "            if (qty <= 0) throw new ArgumentException(\"Quantity must be positive\");",
      "            Items.Add(new OrderItem { Name = name, Price = price, Quantity = qty });",
      "        }",
      "",
      "        public bool RemoveItem(string name)",
      "        {",
      "            return Items.RemoveAll(i => i.Name == name) > 0;",
      "        }",
      "",
      "        public void Cancel()",
      "        {",
      "            if (Status == OrderStatus.Shipped)",
      '                throw new InvalidOperationException("Cannot cancel shipped order");',
      "            Status = OrderStatus.Cancelled;",
      "        }",
      "",
      "        public override string ToString()",
      "        {",
      '            return $"Order #{Id} for {CustomerName} ({Status}): {GetTotal():C}";',
      "        }",
      "    }",
      "",
      "    public class OrderItem",
      "    {",
      "        public string Name { get; set; }",
      "        public decimal Price { get; set; }",
      "        public int Quantity { get; set; }",
      "        public decimal Subtotal => Price * Quantity;",
      "    }",
      "}",
    }
  else
    ext = ".rs"
    lhs = {
      "fn main() {",
      "    let x = 1;",
      "    println!(\"hello\");",
      "}",
    }
    rhs = {
      "fn main() {",
      "    let x = 42;",
      "    let y = 2;",
      "    println!(\"hello world\");",
      "}",
    }
  end
  local tmp1 = vim.fn.tempname() .. ext
  local tmp2 = vim.fn.tempname() .. ext
  vim.fn.writefile(lhs, tmp1)
  vim.fn.writefile(rhs, tmp2)
  M.open(tmp1, tmp2)
end

return M
