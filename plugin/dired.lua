if vim.g.loaded_dired_nvim then
  return
end
vim.g.loaded_dired_nvim = true

vim.api.nvim_create_user_command('Dired', function(o)
  local arg = o.args ~= '' and o.args or nil
  -- inside dired, relative paths are relative to the directory you are looking at
  if arg and arg:sub(1, 1) ~= '/' and arg:sub(1, 1) ~= '~' and require('dired.buf').is_dired(0) then
    arg = require('dired.util').abs(arg, vim.b.dired_dir)
  end
  require('dired').open(arg)
end, { nargs = '?', complete = function(lead)
  return require('dired.complete').candidates(lead)
end, desc = 'Open dired on a directory (default: directory of the current file)' })

vim.api.nvim_create_user_command('DiredCwd', function()
  require('dired').open(vim.fn.getcwd())
end, { desc = 'Open dired on the cwd' })

vim.api.nvim_create_user_command('DiredJump', function()
  require('dired').jump()
end, { desc = 'Open dired on the current file, cursor on it (dired-jump)' })

vim.api.nvim_create_user_command('DiredRoot', function()
  require('dired').open(require('dired').root())
end, { desc = 'Open dired on the project root (see root_markers)' })
