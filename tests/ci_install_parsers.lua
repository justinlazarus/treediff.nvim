-- Install tree-sitter parsers for CI.
-- Usage: nvim --headless -l tests/ci_install_parsers.lua
--
-- -l runs after full startup, so start/ packages are already loaded.

local langs = {
  "rust", "lua", "python", "javascript", "c_sharp", "typescript",
  "css", "json", "yaml", "bash", "html", "toml", "sql", "kotlin", "tsx", "xml",
}

local ok, install = pcall(require, "nvim-treesitter.install")
if ok then
  if install.ensure_installed_sync then
    io.write("Installing parsers via nvim-treesitter.install.ensure_installed_sync...\n")
    install.ensure_installed_sync(langs)
    io.write("Done.\n")
  else
    io.write("ensure_installed_sync not available, trying commands...\n")
    for _, lang in ipairs(langs) do
      pcall(vim.cmd, "TSInstallSync " .. lang)
    end
  end
else
  io.write("WARNING: nvim-treesitter not found\n")
end

vim.cmd("qall!")
