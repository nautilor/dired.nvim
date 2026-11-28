local config = require('dired.config')
local buf = require('dired.buf')
local util = require('dired.util')

local api = vim.api

local M = {}

--- Open a dired buffer for `dir` in the current window.
--- Without `dir`: the directory of the current file when `open_at_current_file`
--- is set (default), else the cwd.
function M.open(dir, opts)
  if dir == nil and config.opts.open_at_current_file then
    return M.jump()
  end
  return buf.open(dir or vim.fn.getcwd(), opts)
end

--- `dired-jump`: dired on the directory of the current file, cursor on the file.
--- (a dired buffer stays on its own directory; other special buffers use the cwd)
function M.jump()
  local name = api.nvim_buf_get_name(0)
  if buf.is_dired(0) then
    return buf.open(vim.b.dired_dir)
  end
  if name == '' or vim.bo.buftype ~= '' then
    return buf.open(vim.fn.getcwd())
  end
  local dir = util.dirname(util.abs(name))
  return buf.open(dir, { file = name })
end

--- Project root for `dir` (default: the directory of the current file / dired buffer).
--- Falls back to the cwd when no marker is found.
function M.root(dir)
  dir = dir or (buf.is_dired(0) and vim.b.dired_dir) or util.dirname(util.abs(api.nvim_buf_get_name(0) ~= '' and api.nvim_buf_get_name(0) or vim.fn.getcwd() .. '/x'))
  return vim.fs.root(dir, config.opts.root_markers) or vim.fn.getcwd()
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
    -- netrw would fight us for directory buffers: stop it if it has not loaded yet
    -- (lazy.nvim runs setup before plugin/ files are sourced) ...
    vim.g.loaded_netrwPlugin = 1
    -- ... and drop its directory autocmds if it already did
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
