local config = require('dired.config')
local buf = require('dired.buf')
local util = require('dired.util')

local api = vim.api

local M = {}

--- Open a dired buffer for `dir` (default: cwd) in the current window.
function M.open(dir, opts)
  return buf.open(dir or vim.fn.getcwd(), opts)
end

--- `dired-jump`: dired on the directory of the current file, cursor on the file.
function M.jump()
  local name = api.nvim_buf_get_name(0)
  if name == '' or vim.bo.buftype ~= '' then
    return M.open(vim.fn.getcwd())
  end
  local dir = util.dirname(util.abs(name))
  return M.open(dir, { file = name })
end

function M.setup(opts)
  config.setup(opts)
  buf.setup_hl()

  local group = api.nvim_create_augroup('Dired', { clear = true })

  api.nvim_create_autocmd('ColorScheme', { group = group, callback = buf.setup_hl })

  api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function(ev)
      if buf.is_dired(ev.buf) then
        buf.win_setup(api.nvim_get_current_win())
      end
    end,
  })

  api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, {
    group = group,
    callback = function(ev)
      if buf.is_dired(ev.buf) then
        buf.maybe_revert(ev.buf)
      end
    end,
  })

  api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(ev)
      if not config.opts.hijack_netrw or buf.is_dired(ev.buf) then
        return
      end
      local name = api.nvim_buf_get_name(ev.buf)
      if name ~= '' and vim.bo[ev.buf].buftype == '' and util.is_dir(name) then
        vim.schedule(function()
          if api.nvim_buf_is_valid(ev.buf) and api.nvim_get_current_buf() == ev.buf then
            buf.open(name, { buf = ev.buf })
          end
        end)
      end
    end,
  })

  if config.opts.hijack_netrw then
    -- netrw would fight us for directory buffers
    pcall(api.nvim_del_augroup_by_name, 'FileExplorer')
    -- directory already open at startup / when setup runs late
    local cur = api.nvim_get_current_buf()
    local name = api.nvim_buf_get_name(cur)
    if name ~= '' and vim.bo[cur].buftype == '' and util.is_dir(name) then
      buf.open(name, { buf = cur })
    end
  end
end

return M
