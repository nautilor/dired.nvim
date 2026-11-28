if vim.g.loaded_dired_nvim then
  return
end
vim.g.loaded_dired_nvim = true

vim.api.nvim_create_user_command('Dired', function(o)
  require('dired').open(o.args ~= '' and o.args or nil)
end, { nargs = '?', complete = 'dir', desc = 'Open dired on a directory (default: directory of the current file)' })

vim.api.nvim_create_user_command('DiredCwd', function()
  require('dired').open(vim.fn.getcwd())
end, { desc = 'Open dired on the cwd' })

vim.api.nvim_create_user_command('DiredJump', function()
  require('dired').jump()
end, { desc = 'Open dired on the current file, cursor on it (dired-jump)' })
