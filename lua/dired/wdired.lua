-- Editable dired (`C-x C-q`): rename files by editing their names in the buffer.
local buf = require('dired.buf')
local util = require('dired.util')

local api = vim.api

local M = {}

local ns = api.nvim_create_namespace('dired_wdired')
local state = {} -- buf -> { [extmark id] = entry }
local write_au = {} -- buf -> BufWriteCmd autocmd id

function M.active(b)
  return vim.b[b].dired_wdired == true
end

function M.enter(b)
  if M.active(b) then
    return
  end
  local items = {}
  vim.b[b].dired_wdired = true
  vim.bo[b].modifiable = true
  vim.bo[b].modified = false
  for _, e in ipairs(buf.entries(b)) do
    if not e.is_dot then
      local id = api.nvim_buf_set_extmark(b, ns, e.lnum - 1, e.col - 1, {
        right_gravity = false,
        invalidate = true,
        undo_restore = false,
      })
      items[id] = e
    end
  end
  state[b] = items
  -- `:w` applies the changes
  vim.bo[b].buftype = 'acwrite'
  write_au[b] = api.nvim_create_autocmd('BufWriteCmd', {
    buffer = b,
    callback = function()
      M.commit(b)
    end,
  })
  require('dired.keymaps').clear(b)
  local function map(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = b, silent = true, desc = 'wdired' })
  end
  map('<C-c><C-c>', function()
    M.commit(b)
  end)
  map('<C-c><C-k>', function()
    M.abort(b)
  end)
  map('<C-c><Esc>', function()
    M.abort(b)
  end)
  util.msg('Edit the names, then :w (or C-c C-c) to apply, C-c C-k to abort')
end

local function leave(b)
  api.nvim_buf_clear_namespace(b, ns, 0, -1)
  state[b] = nil
  if write_au[b] then
    pcall(api.nvim_del_autocmd, write_au[b])
    write_au[b] = nil
  end
  vim.bo[b].buftype = 'nofile'
  vim.b[b].dired_wdired = nil
  vim.bo[b].modifiable = false
  vim.bo[b].modified = false
  for _, lhs in ipairs({ '<C-c><C-c>', '<C-c><C-k>', '<C-c><Esc>' }) do
    pcall(vim.keymap.del, 'n', lhs, { buffer = b })
  end
  require('dired.keymaps').apply(b)
end

function M.abort(b)
  if not M.active(b) then
    return
  end
  leave(b)
  buf.revert(b)
  util.msg('Changes aborted')
end

function M.commit(b)
  if not M.active(b) then
    return
  end
  local pairs_list, extra = {}, {}
  for id, e in pairs(state[b] or {}) do
    local pos = api.nvim_buf_get_extmark_by_id(b, ns, id, { details = true })
    local det = pos and pos[3]
    if pos and #pos > 0 and not (det and det.invalid) then
      local text = api.nvim_buf_get_lines(b, pos[1], pos[1] + 1, false)[1] or ''
      local new = text:sub(pos[2] + 1)
      if e.link then
        new = new:match('^(.-) %-> ') or new
      end
      new = vim.trim(new)
      if new ~= '' and new ~= e.name then
        local dst = new:sub(1, 1) == '/' and util.abs(new) or util.abs(new, e.dir)
        pairs_list[#pairs_list + 1] = { e.path, dst }
        if e.mark ~= ' ' then
          extra[dst] = e.mark
        end
      end
    else
      util.err(('wdired: line of %s was deleted; ignoring'):format(e.name))
    end
  end
  table.sort(pairs_list, function(a, b2)
    return a[1] < b2[1]
  end)
  leave(b)
  if #pairs_list > 0 then
    local n, err = require('dired.fileops').rename_pairs(pairs_list)
    if not n then
      util.err('wdired: ' .. tostring(err))
    else
      util.msg(('%s renamed'):format(util.plural(n, 'file')))
    end
  end
  buf.revert(b, { marks = extra })
  local dirs = {}
  for _, p in ipairs(pairs_list) do
    dirs[util.dirname(p[1])] = true
    dirs[util.dirname(p[2])] = true
  end
  buf.refresh(dirs, extra)
end

return M
