local M = {}
local highlight = require("treediff.highlight")
local render = require("treediff.render")

--- Open two files with tree-aware aligned diff (no :diffthis).
--- @param file1 string
--- @param file2 string
function M.open(file1, file2)
  local treediff = require("treediff")

  -- Save highlights for restoration on close
  M._saved_hl = {
    DiffText = vim.api.nvim_get_hl(0, { name = "DiffText" }),
    DiffChange = vim.api.nvim_get_hl(0, { name = "DiffChange" }),
    DiffAdd = vim.api.nvim_get_hl(0, { name = "DiffAdd" }),
    DiffDelete = vim.api.nvim_get_hl(0, { name = "DiffDelete" }),
  }
  M._saved_fillchars = vim.o.fillchars

  -- Open file1 in current window
  vim.cmd("edit " .. vim.fn.fnameescape(file1))
  local lhs_buf = vim.api.nvim_get_current_buf()
  local lhs_win = vim.api.nvim_get_current_win()

  -- Open file2 in a vertical split
  vim.cmd("vsplit " .. vim.fn.fnameescape(file2))
  local rhs_buf = vim.api.nvim_get_current_buf()
  local rhs_win = vim.api.nvim_get_current_win()

  -- Use vim.schedule so filetype detection completes first (we need ft for lang)
  vim.schedule(function()
    -- Neutralize built-in diff highlights (they'd show if diff mode leaks)
    vim.api.nvim_set_hl(0, "DiffChange", {})
    vim.api.nvim_set_hl(0, "DiffAdd", {})
    vim.api.nvim_set_hl(0, "DiffText", {})
    vim.api.nvim_set_hl(0, "DiffDelete", {})

    -- Run the full tree-aware pipeline
    treediff.view(lhs_buf, rhs_buf)

    -- Track windows for cleanup
    M._lhs_win = lhs_win
    M._rhs_win = rhs_win
  end)
end

--- Close the aligned view and restore highlights.
function M.close()
  pcall(vim.api.nvim_del_augroup_by_name, "treediff_highlight")

  -- Clean up render state
  local wins = {}
  if M._lhs_win then wins[#wins + 1] = M._lhs_win end
  if M._rhs_win then wins[#wins + 1] = M._rhs_win end
  if #wins > 0 then
    render.cleanup(wins)
  else
    -- Fallback: clean all windows in tab
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      highlight.clear(vim.api.nvim_win_get_buf(win))
    end
  end
  M._lhs_win = nil
  M._rhs_win = nil

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
