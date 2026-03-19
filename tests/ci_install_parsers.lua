-- Install tree-sitter parsers for CI.
-- Usage: nvim --headless -l tests/ci_install_parsers.lua
--
-- -l runs after full startup, so start/ packages are already loaded.

local langs = {
  "rust", "lua", "python", "javascript", "c_sharp", "typescript",
  "css", "json", "yaml", "bash", "html", "toml", "sql", "kotlin", "tsx", "xml",
}

local ok, install_mod = pcall(require, "nvim-treesitter.install")
if not ok then
  io.write("WARNING: nvim-treesitter not found, cannot install parsers\n")
  vim.cmd("qall!")
  return
end

-- New API: install() returns an async Task with :wait()
if install_mod.install then
  io.write("Installing parsers via nvim-treesitter.install.install()...\n")
  local task = install_mod.install(langs, { force = true })
  if task and task.wait then
    task:wait()
  else
    -- Give it time to complete if wait isn't available
    vim.wait(60000, function() return false end)
  end
  io.write("Done.\n")
-- Old API: ensure_installed_sync
elseif install_mod.ensure_installed_sync then
  io.write("Installing parsers via ensure_installed_sync...\n")
  install_mod.ensure_installed_sync(langs)
  io.write("Done.\n")
else
  io.write("WARNING: no known install method found\n")
end

vim.cmd("qall!")
