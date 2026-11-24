-- Interactive commands. Every action takes no arguments: it works on the current
-- buffer/cursor and reads the numeric prefix from `vim.v.count` (the `C-u` / ARG of emacs).
local buf = require('dired.buf')
local util = require('dired.util')
local config = require('dired.config')
local marks = require('dired.marks')
local fileops = require('dired.fileops')
local shell = require('dired.shell')
local wdired = require('dired.wdired')
local listing = require('dired.listing')

local api = vim.api

local M = {}
M.list = {} -- name -> { fn, desc }

local function def(name, desc, fn)
  M.list[name] = { fn = fn, desc = desc }
end

local function cnt()
  local c = vim.v.count
  if c and c > 0 then
    return c
  end
end

local function B()
  return api.nvim_get_current_buf()
end

local function lnum()
  return api.nvim_win_get_cursor(0)[1]
end

local function current_dir(b)
  return buf.subdir_at(b, lnum()) or vim.b[b].dired_dir
end

--- files to act on + abort when none
local function files(b, marker)
  local list, kind = buf.get_marked(b, cnt(), marker)
  if #list == 0 then
    if kind == 'none' and marker and marker ~= '*' then
      return nil
    end
    util.err('No file on this line')
    return nil
  end
  return list
end

---------------------------------------------------------------- movement

local function move(n)
  buf.goto_line(lnum() + n)
end

def('next_line', 'dired-next-line', function()
  move(cnt() or 1)
end)
def('prev_line', 'dired-previous-line', function()
  move(-(cnt() or 1))
end)
def('goto_top', 'beginning of buffer', function()
  buf.goto_line(1)
end)

local function dirline(dir)
  local cur = lnum()
  local best
  for _, e in ipairs(buf.entries(B())) do
    if e.type == 'd' then
      if dir > 0 and e.lnum > cur then
        best = e
        break
      elseif dir < 0 and e.lnum < cur then
        best = e
      end
    end
  end
  if best then
    buf.goto_line(best.lnum)
  end
end
def('next_dirline', 'dired-next-dirline', function()
  dirline(1)
end)
def('prev_dirline', 'dired-prev-dirline', function()
  dirline(-1)
end)

def('next_marked', 'dired-next-marked-file', function()
  marks.goto_marked(B(), 1)
end)
def('prev_marked', 'dired-prev-marked-file', function()
  marks.goto_marked(B(), -1)
end)

def('goto_file', 'dired-goto-file', function()
  local b = B()
  local dir = current_dir(b)
  local name = util.ask('Goto file: ', dir .. '/', 'file')
  if not name or name == '' then
    return
  end
  if not buf.goto_path(b, util.abs(name, dir)) then
    util.err(('File %s not found in this buffer'):format(name))
  end
end)

---------------------------------------------------------------- subdirectories

local function subdir_index(b)
  local sds = buf.subdirs(b)
  local cur = lnum()
  local idx
  for i, sd in ipairs(sds) do
    if sd.header <= cur then
      idx = i
    end
  end
  return sds, idx or 1
end

def('next_subdir', 'dired-next-subdir', function()
  local sds, i = subdir_index(B())
  local sd = sds[i + 1] or sds[1]
  buf.goto_line(sd.header)
end)
def('prev_subdir', 'dired-prev-subdir', function()
  local sds, i = subdir_index(B())
  if sds[i] and sds[i].header == lnum() then
    i = i - 1
  end
  local sd = sds[i] or sds[#sds]
  buf.goto_line(sd.header)
end)
def('tree_up', 'dired-tree-up', function()
  local sds, i = subdir_index(B())
  local cur = sds[i].path
  for j = i - 1, 1, -1 do
    local p = sds[j].path
    if cur:sub(1, #p + 1) == (p == '/' and '/' or p .. '/') then
      buf.goto_line(sds[j].header)
      return
    end
  end
  util.err('At top level')
end)
def('tree_down', 'dired-tree-down', function()
  local sds, i = subdir_index(B())
  local cur = sds[i].path
  for j = i + 1, #sds do
    local p = sds[j].path
    if p:sub(1, #cur + 1) == (cur == '/' and '/' or cur .. '/') then
      buf.goto_line(sds[j].header)
      return
    end
  end
  util.err('At bottom level')
end)

def('insert_subdir', 'dired-maybe-insert-subdir', function()
  local b = B()
  local e = buf.file_at(b, lnum())
  local dir
  if e and e.type == 'd' and not e.is_dot then
    dir = e.path
  else
    local d = util.ask('Insert subdirectory: ', current_dir(b) .. '/', 'dir')
    if not d or d == '' then
      return
    end
    dir = util.abs(d, current_dir(b))
  end
  if not util.is_dir(dir) then
    util.err('Not a directory: ' .. dir)
    return
  end
  for _, sd in ipairs(buf.subdirs(b)) do
    if sd.path == dir then
      buf.goto_line(sd.header + 2)
      return
    end
  end
  local switches = vim.b[b].dired_switches or config.opts.switches
  local block = listing.render(dir, switches)
  local sds = buf.subdirs(b)
  local at -- 0-based row to insert at
  local after_last = true
  for _, sd in ipairs(sds) do
    if sd.path > dir then
      at = sd.header - 1
      after_last = false
      break
    end
  end
  buf.modify(b, function()
    if after_last then
      local last = api.nvim_buf_line_count(b)
      local lines = { '' }
      vim.list_extend(lines, block)
      api.nvim_buf_set_lines(b, last, last, false, lines)
    else
      local lines = vim.deepcopy(block)
      lines[#lines + 1] = ''
      api.nvim_buf_set_lines(b, at, at, false, lines)
    end
  end)
  buf.decorate(b)
  buf.goto_path(b, dir)
  for _, sd in ipairs(buf.subdirs(b)) do
    if sd.path == dir then
      buf.goto_line(sd.first)
      -- skip . and ..
      buf.goto_first_file(b)
      for _, en in ipairs(buf.entries(b)) do
        if en.dir == dir and not en.is_dot then
          buf.goto_line(en.lnum)
          break
        end
      end
    end
  end
end)

local function toggle_fold(first, last)
  vim.wo.foldmethod = 'manual'
  if vim.fn.foldclosed(first) ~= -1 then
    vim.cmd(('%d,%dfoldopen'):format(first, last))
  else
    vim.cmd(('%d,%dfold'):format(first, last))
  end
end

def('hide_subdir', 'dired-hide-subdir', function()
  local b = B()
  local sds, i = subdir_index(b)
  local sd = sds[i]
  toggle_fold(sd.header + 1, math.max(sd.last, sd.header + 1))
  buf.goto_line(sd.header)
end)

def('hide_all', 'dired-hide-all', function()
  local b = B()
  vim.wo.foldmethod = 'manual'
  local sds = buf.subdirs(b)
  local any_open = false
  for _, sd in ipairs(sds) do
    if vim.fn.foldclosed(sd.header + 1) == -1 then
      any_open = true
    end
  end
  for _, sd in ipairs(sds) do
    local a, z = sd.header + 1, math.max(sd.last, sd.header + 1)
    if any_open then
      if vim.fn.foldclosed(a) == -1 then
        vim.cmd(('%d,%dfold'):format(a, z))
      end
    else
      pcall(vim.cmd, ('%d,%dfoldopen'):format(a, z))
    end
  end
end)

def('kill_lines', 'dired-do-kill-lines', function()
  local b = B()
  local cur = lnum()
  local c = cnt()
  if not c and buf.is_header(b, cur) then
    -- kill whole subdirectory
    local sds, i = subdir_index(b)
    local sd = sds[i]
    buf.modify(b, function()
      local first, last = sd.header, sd.last
      if last < api.nvim_buf_line_count(b) then
        last = last + 1 -- trailing blank
      elseif first > 1 then
        first = first - 1 -- leading blank
      end
      api.nvim_buf_set_lines(b, first - 1, last, false, {})
    end)
    buf.decorate(b)
    buf.goto_line(math.min(cur, api.nvim_buf_line_count(b)))
    return
  end
  local victims = {}
  if c then
    for l = cur, math.min(cur + c - 1, api.nvim_buf_line_count(b)) do
      victims[#victims + 1] = l
    end
  else
    for _, e in ipairs(buf.entries(b)) do
      if e.mark == '*' then
        victims[#victims + 1] = e.lnum
      end
    end
    if #victims == 0 and buf.file_at(b, cur) then
      victims[1] = cur
    end
  end
  buf.modify(b, function()
    for i = #victims, 1, -1 do
      api.nvim_buf_set_lines(b, victims[i] - 1, victims[i], false, {})
    end
  end)
  buf.decorate(b)
  buf.goto_line(math.min(cur, api.nvim_buf_line_count(b)))
  util.msg(('Killed %s (files not deleted)'):format(util.plural(#victims, 'line')))
end)

---------------------------------------------------------------- visiting

local function visit(path, how)
  local b = B()
  local old = b
  if how == 'other' or how == 'display' then
    local cur = api.nvim_get_current_win()
    local wins = api.nvim_tabpage_list_wins(0)
    if #wins == 1 then
      vim.cmd('split')
    else
      vim.cmd('wincmd w')
    end
    if util.is_dir(path) then
      require('dired').open(path)
    else
      vim.cmd.edit(vim.fn.fnameescape(path))
    end
    if how == 'display' then
      api.nvim_set_current_win(cur)
    end
    return
  end
  if util.is_dir(path) then
    require('dired').open(path)
  elseif how == 'view' then
    vim.cmd('view ' .. vim.fn.fnameescape(path))
  else
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  if how == 'alternate' and api.nvim_buf_is_valid(old) and old ~= B() and #vim.fn.win_findbuf(old) == 0 then
    pcall(api.nvim_buf_delete, old, { force = true })
  end
end

local function find_current(how)
  return function()
    local b = B()
    local e = buf.file_at(b, lnum())
    if not e then
      if buf.is_header(b, lnum()) then
        visit(buf.subdir_at(b, lnum()), how)
      else
        util.err('No file on this line')
      end
      return
    end
    visit(e.path, how)
  end
end

def('find_file', 'dired-find-file', find_current('edit'))
def('find_file_other_window', 'dired-find-file-other-window', find_current('other'))
def('display_file', 'dired-display-file', find_current('display'))
def('view_file', 'dired-view-file', find_current('view'))
def('find_alternate_file', 'dired-find-alternate-file', find_current('alternate'))

def('up_directory', 'dired-up-directory', function()
  local b = B()
  local dir = current_dir(b)
  if dir == '/' then
    util.msg('Already at root')
    return
  end
  require('dired').open(util.dirname(dir), { file = dir })
end)

---------------------------------------------------------------- marking

def('mark', 'dired-mark', function()
  marks.mark_lines(B(), cnt() or 1, '*')
end)
def('unmark', 'dired-unmark', function()
  marks.mark_lines(B(), cnt() or 1, ' ')
end)
def('flag_delete', 'dired-flag-file-deletion', function()
  marks.mark_lines(B(), cnt() or 1, 'D')
end)
def('unmark_backward', 'dired-unmark-backward', function()
  marks.unmark_backward(B(), cnt() or 1)
end)
def('unmark_all', 'dired-unmark-all-marks', function()
  marks.unmark_all(B())
end)
def('unmark_all_files', 'dired-unmark-all-files', function()
  marks.unmark_all_files(B())
end)
def('toggle_marks', 'dired-toggle-marks', function()
  marks.toggle(B())
end)
def('change_marks', 'dired-change-marks', function()
  marks.change_marks(B())
end)
def('mark_executables', 'dired-mark-executables', function()
  marks.mark_executables(B())
end)
def('mark_directories', 'dired-mark-directories', function()
  marks.mark_directories(B())
end)
def('mark_symlinks', 'dired-mark-symlinks', function()
  marks.mark_symlinks(B())
end)
def('mark_subdir_files', 'dired-mark-subdir-files', function()
  marks.mark_subdir_files(B())
end)
def('mark_extension', 'dired-mark-extension', function()
  marks.mark_extension(B())
end)
def('mark_regexp', 'dired-mark-files-regexp (count: match full path)', function()
  marks.mark_regexp(B(), '*', 'Mark files (regexp): ', cnt() ~= nil)
end)
def('flag_regexp', 'dired-flag-files-regexp (count: match full path)', function()
  marks.mark_regexp(B(), 'D', 'Flag for deletion (regexp): ', cnt() ~= nil)
end)
def('mark_containing', 'dired-mark-files-containing-regexp', function()
  marks.mark_containing(B())
end)
def('flag_garbage', 'dired-flag-garbage-files', function()
  marks.flag_garbage(B())
end)
def('flag_backups', 'dired-flag-backup-files (count: unflag)', function()
  marks.flag_backups(B(), cnt() ~= nil)
end)
def('flag_autosave', 'dired-flag-auto-save-files (count: unflag)', function()
  marks.flag_autosave(B(), cnt() ~= nil)
end)
def('clean_directory', 'dired-clean-directory (numbered backups)', function()
  marks.clean_directory(B(), cnt())
end)

---------------------------------------------------------------- file operations

def('copy', 'dired-do-copy', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.copy(b, f)
  end
end)
def('rename', 'dired-do-rename', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.rename(b, f)
  end
end)
def('delete', 'dired-do-delete', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.delete(b, f)
  end
end)
def('do_flagged_delete', 'dired-do-flagged-delete', function()
  local b = B()
  local list = buf.get_marked(b, nil, 'D')
  if #list == 0 then
    util.msg('(No deletions requested)')
    return
  end
  fileops.delete(b, list, true)
end)
def('symlink', 'dired-do-symlink', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.symlink(b, f)
  end
end)
def('relsymlink', 'dired-do-relsymlink', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.relsymlink(b, f)
  end
end)
def('hardlink', 'dired-do-hardlink', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.hardlink(b, f)
  end
end)
def('create_directory', 'dired-create-directory', function()
  fileops.create_directory(B())
end)
def('chmod', 'dired-do-chmod', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.chmod(b, f)
  end
end)
def('chown', 'dired-do-chown', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.chown(b, f)
  end
end)
def('chgrp', 'dired-do-chgrp', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.chgrp(b, f)
  end
end)
def('touch', 'dired-do-touch', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.touch(b, f)
  end
end)
def('compress', 'dired-do-compress', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.compress(b, f)
  end
end)
def('compress_to', 'dired-do-compress-to', function()
  local b = B()
  local f = files(b)
  if f then
    fileops.compress_to(b, f)
  end
end)

local function regexp_op(name, desc, fn)
  def(name, desc .. ' (count: match full path)', function()
    local b = B()
    local list = buf.get_marked(b, nil, '*')
    if #list == 0 then
      local e = buf.file_at(b, lnum())
      list = e and { e } or {}
    end
    if #list == 0 then
      util.err('No file on this line')
      return
    end
    fn(b, list, cnt() ~= nil)
  end)
end
regexp_op('rename_regexp', 'dired-do-rename-regexp', fileops.rename_regexp)
regexp_op('copy_regexp', 'dired-do-copy-regexp', fileops.copy_regexp)
regexp_op('hardlink_regexp', 'dired-do-hardlink-regexp', fileops.hardlink_regexp)
regexp_op('symlink_regexp', 'dired-do-symlink-regexp', fileops.symlink_regexp)
regexp_op('relsymlink_regexp', 'dired-do-relsymlink-regexp', fileops.relsymlink_regexp)
regexp_op('upcase', 'dired-upcase', function(b, f)
  fileops.upcase(b, f)
end)
regexp_op('downcase', 'dired-downcase', function(b, f)
  fileops.downcase(b, f)
end)

---------------------------------------------------------------- shell & friends

def('shell_command', 'dired-do-shell-command', function()
  local b = B()
  local f = files(b)
  if f then
    shell.shell_command(b, f, false)
  end
end)
def('async_shell_command', 'dired-do-async-shell-command', function()
  local b = B()
  local f = files(b)
  if f then
    shell.shell_command(b, f, true)
  end
end)
def('diff', 'dired-diff', function()
  shell.diff(B())
end)
def('find_regexp', 'dired-do-find-regexp (quickfix)', function()
  local b = B()
  local f = files(b)
  if f then
    shell.find_regexp(b, f)
  end
end)
def('query_replace', 'dired-do-find-regexp-and-replace', function()
  local b = B()
  local f = files(b)
  if f then
    shell.query_replace(b, f)
  end
end)

---------------------------------------------------------------- misc

def('revert', 'revert-buffer (keeps marks)', function()
  buf.revert(B())
end)
def('redisplay', 'dired-do-redisplay', function()
  buf.revert(B())
end)

def('sort_toggle', 'dired-sort-toggle-or-edit (count: edit switches)', function()
  local b = B()
  local sw = vim.b[b].dired_switches or config.opts.switches
  if cnt() then
    local new = util.ask('ls switches (must contain -l): ', sw)
    if not new or new == '' then
      return
    end
    sw = new
  elseif sw:find('t') and sw:match('^%-%a*t') then
    sw = sw:gsub('^(%-%a*)t', '%1')
  else
    sw = sw:gsub('^(%-%a*)', '%1t', 1)
  end
  vim.b[b].dired_switches = sw
  buf.revert(b)
  util.msg('Dired listing switches: ' .. sw)
end)

def('toggle_details', 'dired-hide-details-mode', function()
  local b = B()
  vim.b[b].dired_hide_details = not vim.b[b].dired_hide_details
  buf.decorate(b)
end)

local function names(abs)
  local b = B()
  local list = buf.get_marked(b, cnt(), '*')
  local out = {}
  for _, e in ipairs(list) do
    if abs == true then
      out[#out + 1] = e.path
    elseif abs == 'rel' then
      out[#out + 1] = util.relpath(vim.b[b].dired_dir, e.path)
    else
      out[#out + 1] = e.name
    end
  end
  return out
end

local function copy_names(list)
  if #list == 0 then
    util.err('No file on this line')
    return
  end
  local s = table.concat(list, ' ')
  vim.fn.setreg('"', s)
  pcall(vim.fn.setreg, '+', s)
  util.msg(s)
end
def('copy_filename', 'dired-copy-filename-as-kill (count: relative path)', function()
  copy_names(names(cnt() and 'rel' or false))
end)
def('copy_filename_abs', 'dired-copy-filename-as-kill (absolute)', function()
  copy_names(names(true))
end)

def('show_file_type', 'dired-show-file-type', function()
  local e = buf.file_at(B(), lnum())
  if not e then
    return
  end
  local res = vim.system({ 'file', '--', e.path }, { text = true }):wait()
  util.msg(vim.trim(res.stdout or res.stderr or ''))
end)

def('browse_url', 'browse-url-of-dired-file', function()
  local e = buf.file_at(B(), lnum())
  if e then
    vim.ui.open(e.path)
  end
end)

def('load', 'dired-do-load (source lua/vim files)', function()
  local list = files(B())
  for _, f in ipairs(list or {}) do
    local ok, err = pcall(vim.cmd.source, vim.fn.fnameescape(f.path))
    if not ok then
      util.err(tostring(err))
    end
  end
end)

def('quit', 'quit-window', function()
  if #api.nvim_tabpage_list_wins(0) > 1 then
    vim.cmd('close')
  else
    local b = B()
    if not pcall(vim.cmd, 'buffer #') or B() == b then
      vim.cmd('enew')
    end
  end
end)

def('summary', 'dired-summary', function()
  util.msg('d-elete, u-ndelete, x-punge, f-ind, o-ther window, R-ename, C-opy, h-elp')
end)

def('wdired', 'wdired-change-to-wdired-mode (C-x C-q)', function()
  wdired.enter(B())
end)

def('help', 'describe-mode', function()
  local keymaps = require('dired.keymaps')
  local lines = { 'Dired key bindings (q to close)', '' }
  local rows = {}
  for lhs, action in pairs(keymaps.merged()) do
    local a = M.list[action]
    rows[#rows + 1] = { lhs, a and a.desc or action }
  end
  table.sort(rows, function(x, y)
    return x[2] == y[2] and x[1] < y[1] or x[2] < y[2]
  end)
  for _, r in ipairs(rows) do
    lines[#lines + 1] = ('%-14s %s'):format(r[1], r[2])
  end
  local hb = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(hb, 0, -1, false, lines)
  vim.bo[hb].modifiable = false
  vim.bo[hb].bufhidden = 'wipe'
  local w = math.min(70, vim.o.columns - 4)
  local h = math.min(#lines, vim.o.lines - 6)
  local win = api.nvim_open_win(hb, true, {
    relative = 'editor',
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    border = 'rounded',
    style = 'minimal',
  })
  vim.keymap.set('n', 'q', function()
    pcall(api.nvim_win_close, win, true)
  end, { buffer = hb, nowait = true })
end)

return M
