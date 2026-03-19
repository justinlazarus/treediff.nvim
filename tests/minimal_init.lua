-- Minimal init for headless testing.
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(plugin_root)
vim.cmd("set noswapfile")

require("treediff").setup()
