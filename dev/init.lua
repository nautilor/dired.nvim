-- Throwaway config used by dev/run.sh. Nothing here touches your real nvim config.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.termguicolors = true
vim.g.mapleader = ' '

local function load()
  require('dired').setup({ preset = vim.env.DIRED_PRESET or 'emacs' })
end
load()

-- :DiredReload  -> pick up code changes without restarting nvim
vim.api.nvim_create_user_command('DiredReload', function()
  for name in pairs(package.loaded) do
    if name == 'dired' or name:match('^dired%.') then
      package.loaded[name] = nil
    end
  end
  vim.g.loaded_dired_nvim = nil
  dofile(root .. '/plugin/dired.lua')
  load()
  -- re-apply keymaps on live dired buffers
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if require('dired.buf').is_dired(b) then
      require('dired.keymaps').apply(b)
    end
  end
  vim.notify('dired reloaded')
end, {})

-- handy while testing
vim.keymap.set('n', '-', '<Cmd>DiredJump<CR>', { desc = 'dired-jump' })
vim.keymap.set('n', '<leader>d', '<Cmd>Dired<CR>', { desc = 'dired cwd' })
