-- Mark commands: m u d U t * % ~ # .
local buf = require('dired.buf')
local util = require('dired.util')
local config = require('dired.config')

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

local function cur_lnum()
  return api.nvim_win_get_cursor(0)[1]
end

--- Mark `n` lines (default 1) from the cursor with `char`, then move past them.
--- Mirrors `dired-repeat-over-lines`.
function M.mark_lines(b, n, char)
  n = n or 1
  local step = n >= 0 and 1 or -1
  local lnum = cur_lnum()
  if n < 0 then
    lnum = lnum - 1
  end
  local last = api.nvim_buf_line_count(b)
  for _ = 1, math.abs(n) do
    if lnum < 1 or lnum > last then
      break
    end
    if buf.file_at(b, lnum) then
      buf.set_mark(b, lnum, char)
    end
    lnum = lnum + step
  end
  if n < 0 then
    lnum = lnum + 1
  end
  buf.goto_line(lnum)
end

function M.unmark_backward(b, n)
  M.mark_lines(b, -(n or 1), ' ')
end

--- Set `char` on every non-dot entry for which pred(entry) is true. Returns count.
function M.mark_if(b, pred, char)
  local n = 0
  for _, e in ipairs(buf.entries(b)) do
    if not e.is_dot and pred(e) then
      if e.mark ~= char then
        buf.set_mark(b, e.lnum, char)
      end
      n = n + 1
    end
  end
  return n
end

local function report(n, what)
  util.msg(('%s %s'):format(util.plural(n, 'file'), what))
end

function M.unmark_all(b, only)
  local n = 0
  for _, e in ipairs(buf.entries(b)) do
    if e.mark ~= ' ' and (only == nil or e.mark == only) then
      buf.set_mark(b, e.lnum, ' ')
      n = n + 1
    end
  end
  util.msg(('%s unmarked'):format(util.plural(n, 'mark')))
end

--- `M-DEL`: ask which mark to remove (RET = all)
function M.unmark_all_files(b)
  local c = util.ask('Remove marks (RET means all): ')
  if c == nil then
    return
  end
  M.unmark_all(b, c ~= '' and c:sub(1, 1) or nil)
end

function M.toggle(b)
  for _, e in ipairs(buf.entries(b)) do
    if not e.is_dot then
      if e.mark == ' ' then
        buf.set_mark(b, e.lnum, '*')
      elseif e.mark == '*' then
        buf.set_mark(b, e.lnum, ' ')
      end
    end
  end
end

function M.change_marks(b)
  local old = util.ask("Change from mark (default '*'): ")
  if old == nil then
    return
  end
  local new = util.ask("Change to mark (default ' '): ")
  if new == nil then
    return
  end
  old = old ~= '' and old:sub(1, 1) or '*'
  new = new ~= '' and new:sub(1, 1) or ' '
  for _, e in ipairs(buf.entries(b)) do
    if e.mark == old then
      buf.set_mark(b, e.lnum, new)
    end
  end
end

---------------------------------------------------------------- by kind

function M.mark_directories(b, char)
  report(M.mark_if(b, function(e)
    return e.type == 'd'
  end, char or '*'), 'marked')
end

function M.mark_symlinks(b, char)
  report(M.mark_if(b, function(e)
    return e.type == 'l'
  end, char or '*'), 'marked')
end

function M.mark_executables(b, char)
  report(M.mark_if(b, function(e)
    return e.type == '-' and (e.perms:sub(4, 4):match('[xs]') or e.perms:sub(7, 7):match('[xs]') or e.perms:sub(10, 10):match('[xt]')) ~= nil
  end, char or '*'), 'marked')
end

function M.mark_extension(b)
  local ext = util.ask('Marking files with extension: ')
  if not ext or ext == '' then
    return
  end
  ext = ext:gsub('^%.', '')
  local suffix = '.' .. ext
  report(M.mark_if(b, function(e)
    return e.name:sub(-#suffix) == suffix
  end, '*'), 'marked')
end

function M.mark_subdir_files(b)
  local dir = buf.subdir_at(b, cur_lnum())
  report(M.mark_if(b, function(e)
    return e.dir == dir
  end, '*'), 'marked')
end

---------------------------------------------------------------- by regexp

--- % m / % d : `whole` matches the full path instead of the bare name
function M.mark_regexp(b, char, prompt, whole)
  local re = util.ask(prompt or 'Mark files (regexp): ')
  if not re or re == '' then
    return
  end
  local matcher, err = util.compile(re)
  if not matcher then
    util.err(err)
    return
  end
  local n = M.mark_if(b, function(e)
    return matcher(whole and e.path or e.name)
  end, char or '*')
  report(n, char == 'D' and 'flagged' or 'marked')
end

local function read_file(path)
  local st = uv.fs_stat(path)
  if not st or st.type ~= 'file' then
    return nil
  end
  local f = io.open(path, 'rb')
  if not f then
    return nil
  end
  local data = f:read('*a')
  f:close()
  return data
end

--- % g : mark files whose *contents* match
function M.mark_containing(b)
  local re = util.ask('Mark files containing (regexp): ')
  if not re or re == '' then
    return
  end
  local matcher, err = util.compile(re)
  if not matcher then
    util.err(err)
    return
  end
  report(M.mark_if(b, function(e)
    local data = read_file(e.path)
    return data ~= nil and matcher(data)
  end, '*'), 'marked')
end

--- % &
function M.flag_garbage(b)
  local matcher = util.compile(config.opts.garbage_files_regexp)
  report(M.mark_if(b, function(e)
    return matcher(e.name)
  end, 'D'), 'flagged')
end

--- ~  (count = unflag instead)
function M.flag_backups(b, unflag)
  local char = unflag and ' ' or 'D'
  local n = M.mark_if(b, function(e)
    return e.name:sub(-1) == '~' and e.type ~= 'd'
  end, char)
  report(n, unflag and 'unflagged' or 'flagged')
end

--- #
function M.flag_autosave(b, unflag)
  local char = unflag and ' ' or 'D'
  local n = M.mark_if(b, function(e)
    return e.name:match('^#.*#$') ~= nil
  end, char)
  report(n, unflag and 'unflagged' or 'flagged')
end

--- .  flag excess numerical backups (foo.~3~)
function M.clean_directory(b, keep)
  local new_keep, old_keep = config.opts.kept_versions, config.opts.kept_old_versions
  if keep then
    new_keep = keep
  end
  local groups = {}
  for _, e in ipairs(buf.entries(b)) do
    local base, ver = e.name:match('^(.*)%.~(%d+)~$')
    if base then
      local key = e.dir .. '/' .. base
      groups[key] = groups[key] or {}
      table.insert(groups[key], { e = e, v = tonumber(ver) })
    end
  end
  local n = 0
  for _, list in pairs(groups) do
    table.sort(list, function(x, y)
      return x.v < y.v
    end)
    for i = old_keep + 1, #list - new_keep do
      buf.set_mark(b, list[i].e.lnum, 'D')
      n = n + 1
    end
  end
  util.msg(('Cleaning numerical backups (keeping %d new, %d old): %s flagged'):format(new_keep, old_keep, util.plural(n, 'file')))
end

---------------------------------------------------------------- navigation

--- dired-next-marked-file / prev
function M.goto_marked(b, dir)
  local cur = cur_lnum()
  local entries = buf.entries(b)
  local found
  local function marked(e)
    return e.mark ~= ' '
  end
  if dir > 0 then
    for _, e in ipairs(entries) do
      if e.lnum > cur and marked(e) then
        found = e
        break
      end
    end
    if not found then
      for _, e in ipairs(entries) do
        if marked(e) then
          found = e
          break
        end
      end
    end
  else
    for i = #entries, 1, -1 do
      local e = entries[i]
      if e.lnum < cur and marked(e) then
        found = e
        break
      end
    end
    if not found then
      for i = #entries, 1, -1 do
        if marked(entries[i]) then
          found = entries[i]
          break
        end
      end
    end
  end
  if found then
    buf.goto_line(found.lnum)
  else
    util.msg('No next marked file')
  end
end

return M
