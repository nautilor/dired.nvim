-- Core buffer model: subdirectories, entries, marks, revert, open.
local config = require('dired.config')
local util = require('dired.util')
local listing = require('dired.listing')

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

M.ns = api.nvim_create_namespace('dired')

local function lines_of(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

function M.is_dired(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  return api.nvim_buf_is_valid(buf) and vim.b[buf].dired_dir ~= nil
end

--- Run fn with the buffer temporarily modifiable.
function M.modify(buf, fn)
  local was_mod = vim.bo[buf].modifiable
  local was_modified = vim.bo[buf].modified
  vim.bo[buf].modifiable = true
  local ok, err = pcall(fn)
  vim.bo[buf].modifiable = was_mod
  vim.bo[buf].modified = was_modified and was_mod or false
  if not ok then
    error(err, 0)
  end
end

---------------------------------------------------------------- structure

function M.path_of(dir, name)
  if name == '.' then
    return dir
  elseif name == '..' then
    return util.dirname(dir)
  end
  return util.join(dir, name)
end

--- All subdirectories in buffer order: { path, header, first, last } (1-based lines)
function M.subdirs(buf)
  local lines = lines_of(buf)
  local res, i = {}, 1
  while i <= #lines do
    local p = lines[i]:match('^  (/.*):$')
    if p then
      local j = i + 1
      while j <= #lines and lines[j] ~= '' do
        j = j + 1
      end
      res[#res + 1] = { path = p, header = i, first = i + 2, last = j - 1 }
      i = j
    else
      i = i + 1
    end
  end
  return res
end

--- Directory path (and header line) containing line `lnum`.
function M.subdir_at(buf, lnum)
  local lines = api.nvim_buf_get_lines(buf, 0, lnum, false)
  for i = #lines, 1, -1 do
    local p = lines[i]:match('^  (/.*):$')
    if p then
      return p, i
    end
  end
end

function M.is_header(buf, lnum)
  local l = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  return l ~= nil and l:match('^  /.*:$') ~= nil
end

--- Entry on a line (nil if none): listing.parse fields + dir, path, lnum
function M.file_at(buf, lnum)
  local text = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  if not text then
    return nil
  end
  local info = listing.parse(text)
  if not info then
    return nil
  end
  local dir = M.subdir_at(buf, lnum)
  if not dir then
    return nil
  end
  info.dir = dir
  info.lnum = lnum
  info.path = M.path_of(dir, info.name)
  return info
end

--- All entries of the buffer, in order.
function M.entries(buf)
  local res, dir = {}, nil
  for i, l in ipairs(lines_of(buf)) do
    local p = l:match('^  (/.*):$')
    if p then
      dir = p
    elseif dir and l ~= '' then
      local info = listing.parse(l)
      if info then
        info.dir = dir
        info.lnum = i
        info.path = M.path_of(dir, info.name)
        res[#res + 1] = info
      end
    end
  end
  return res
end

function M.find_line(buf, path)
  local dir, name = util.dirname(path), util.basename(path)
  local cur
  local lines = lines_of(buf)
  for i, l in ipairs(lines) do
    local p = l:match('^  (/.*):$')
    if p then
      cur = p
    elseif cur == dir then
      local info = listing.parse(l)
      if info and info.name == name then
        return i, info
      end
    end
  end
  for i, l in ipairs(lines) do
    if l == '  ' .. path .. ':' then
      return i
    end
  end
end

---------------------------------------------------------------- cursor

function M.goto_line(lnum, win)
  win = win or 0
  local buf = api.nvim_win_get_buf(win)
  local last = api.nvim_buf_line_count(buf)
  lnum = math.max(1, math.min(last, lnum))
  local text = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
  local info = listing.parse(text)
  api.nvim_win_set_cursor(win, { lnum, info and (info.col - 1) or 0 })
end

function M.goto_path(buf, path, win)
  local lnum = M.find_line(buf, path)
  if not lnum then
    return false
  end
  win = win or 0
  if api.nvim_win_get_buf(win) == buf then
    M.goto_line(lnum, win)
    api.nvim_win_call(win, function()
      pcall(vim.cmd, 'normal! zv')
    end)
  end
  return true
end

function M.goto_first_file(buf, win)
  local first
  for _, e in ipairs(M.entries(buf)) do
    first = first or e
    if not e.is_dot then
      M.goto_line(e.lnum, win)
      return
    end
  end
  if first then
    M.goto_line(first.lnum, win)
  end
end

---------------------------------------------------------------- marks

function M.set_mark(buf, lnum, char)
  M.modify(buf, function()
    api.nvim_buf_set_text(buf, lnum - 1, 0, lnum - 1, 1, { char })
  end)
  M.decorate_line(buf, lnum)
end

--- Entries to operate on. Mirrors `dired-get-marked-files`.
--- returns list, kind ('count'|'marked'|'current'|'none')
function M.get_marked(buf, count, marker)
  marker = marker or '*'
  local cur = api.nvim_win_get_cursor(0)[1]
  if count then
    local res = {}
    local last = api.nvim_buf_line_count(buf)
    for l = cur, math.min(cur + count - 1, last) do
      local e = M.file_at(buf, l)
      if e then
        res[#res + 1] = e
      end
    end
    return res, 'count'
  end
  local res = {}
  for _, e in ipairs(M.entries(buf)) do
    if e.mark == marker then
      res[#res + 1] = e
    end
  end
  if #res > 0 then
    return res, 'marked'
  end
  if marker == '*' then
    local e = M.file_at(buf, cur)
    if e then
      return { e }, 'current'
    end
  end
  return {}, 'none'
end

---------------------------------------------------------------- highlighting

function M.setup_hl()
  local function hl(name, link)
    api.nvim_set_hl(0, name, { link = link, default = true })
  end
  hl('DiredHeader', 'Title')
  hl('DiredDirectory', 'Directory')
  hl('DiredSymlink', 'Constant')
  hl('DiredMark', 'WarningMsg')
  hl('DiredMarked', 'WarningMsg')
  hl('DiredFlagged', 'DiagnosticError')
  hl('DiredFlagMark', 'DiagnosticError')
  hl('DiredExecutable', 'DiagnosticOk')
  hl('DiredSpecial', 'DiagnosticWarn')
  hl('DiredPermRead', 'DiagnosticWarn')
  hl('DiredPermWrite', 'DiagnosticError')
  hl('DiredPermExec', 'DiagnosticOk')
  hl('DiredPermNone', 'Comment')
  hl('DiredPermType', 'Directory')
  hl('DiredLinks', 'Number')
  hl('DiredOwner', 'Identifier')
  hl('DiredGroup', 'Type')
  hl('DiredSize', 'Number')
  hl('DiredDate', 'Special')
end

local function decorate(buf, row, text)
  local function mark(col, opts)
    api.nvim_buf_set_extmark(buf, M.ns, row, col, opts)
  end
  if text:match('^  /.*:$') then
    mark(2, { end_col = #text - 1, hl_group = 'DiredHeader' })
    return
  end
  local info = listing.parse(text)
  if not info then
    return
  end
  local name_hl
  if info.mark == '*' then
    mark(0, { end_col = 1, hl_group = 'DiredMark' })
    name_hl = 'DiredMarked'
  elseif info.mark == 'D' then
    mark(0, { end_col = 1, hl_group = 'DiredFlagMark' })
    name_hl = 'DiredFlagged'
  elseif info.mark ~= ' ' then
    mark(0, { end_col = 1, hl_group = 'DiredMark' })
  end
  local colors = config.colors()
  if not name_hl then
    if info.type == 'd' then
      name_hl = 'DiredDirectory'
    elseif info.type == 'l' then
      name_hl = 'DiredSymlink'
    elseif colors.filetype then
      if info.type:match('[cbps]') then
        name_hl = 'DiredSpecial'
      elseif info.type == '-' and (info.perms:sub(4, 4):match('[xs]') or info.perms:sub(7, 7):match('[xs]') or info.perms:sub(10, 10):match('[xt]')) then
        name_hl = 'DiredExecutable'
      end
    end
  end
  local f = (colors.permissions or colors.links or colors.owner or colors.group or colors.size or colors.date) and listing.fields(text, info)
  if f then
    if colors.permissions then
      local PERM = { r = 'DiredPermRead', w = 'DiredPermWrite', x = 'DiredPermExec', s = 'DiredPermExec', S = 'DiredPermExec', t = 'DiredPermExec', T = 'DiredPermExec' }
      mark(f.perms[1], { end_col = f.perms[1] + 1, hl_group = 'DiredPermType' })
      for c = f.perms[1] + 1, f.perms[2] - 1 do
        mark(c, { end_col = c + 1, hl_group = PERM[text:sub(c + 1, c + 1)] or 'DiredPermNone' })
      end
    end
    for _, k in ipairs({ 'links', 'owner', 'group', 'size', 'date' }) do
      if colors[k] and f[k] then
        mark(f[k][1], { end_col = f[k][2], hl_group = ({ links = 'DiredLinks', owner = 'DiredOwner', group = 'DiredGroup', size = 'DiredSize', date = 'DiredDate' })[k] })
      end
    end
  end
  if name_hl then
    mark(info.col - 1, { end_col = info.col - 1 + #info.name, hl_group = name_hl })
  end
  if vim.b[buf].dired_hide_details then
    mark(2, { end_col = info.col - 1, conceal = '' })
    if info.link then
      mark(info.col - 1 + #info.name, { end_col = #text, conceal = '' })
    end
  end
end

function M.decorate_line(buf, lnum)
  api.nvim_buf_clear_namespace(buf, M.ns, lnum - 1, lnum)
  local text = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  if text then
    decorate(buf, lnum - 1, text)
  end
end

function M.decorate(buf)
  api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for i, l in ipairs(lines_of(buf)) do
    decorate(buf, i - 1, l)
  end
end

---------------------------------------------------------------- revert

local function signature(buf)
  local sum = 0
  for _, sd in ipairs(M.subdirs(buf)) do
    local st = uv.fs_stat(sd.path)
    if st then
      sum = sum + st.mtime.sec + st.mtime.nsec / 1e9
    end
  end
  return sum
end

--- Re-read every subdirectory, keeping marks (by path). `opts.marks`: { [path] = char }
function M.revert(buf, opts)
  opts = opts or {}
  local views = {}
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    local cur = api.nvim_win_get_cursor(w)
    local e = M.file_at(buf, cur[1])
    local hdr = (not e) and M.is_header(buf, cur[1]) and M.subdir_at(buf, cur[1]) or nil
    views[w] = { lnum = cur[1], path = e and e.path or hdr }
  end

  local marks = {}
  for _, e in ipairs(M.entries(buf)) do
    if e.mark ~= ' ' then
      marks[e.path] = e.mark
    end
  end
  for p, c in pairs(opts.marks or {}) do
    marks[p] = (c ~= ' ') and c or nil
  end

  local dirs = {}
  for i, sd in ipairs(M.subdirs(buf)) do
    if i == 1 or util.is_dir(sd.path) then
      dirs[#dirs + 1] = sd.path
    end
  end
  if #dirs == 0 then
    dirs[1] = vim.b[buf].dired_dir
  end

  local switches = vim.b[buf].dired_switches or config.opts.switches
  local out = {}
  for i, d in ipairs(dirs) do
    if i > 1 then
      out[#out + 1] = ''
    end
    for _, l in ipairs(listing.render(d, switches)) do
      local info = listing.parse(l)
      if info then
        local m = marks[M.path_of(d, info.name)]
        if m then
          l = m .. l:sub(2)
        end
      end
      out[#out + 1] = l
    end
  end

  M.modify(buf, function()
    api.nvim_buf_set_lines(buf, 0, -1, false, out)
  end)
  M.decorate(buf)
  vim.b[buf].dired_sig = signature(buf)

  for w, v in pairs(views) do
    if api.nvim_win_is_valid(w) then
      local ok = false
      if v.path then
        ok = M.goto_path(buf, v.path, w)
      end
      if not ok then
        M.goto_line(v.lnum, w)
      end
    end
  end
end

--- Revert every dired buffer showing one of `dirs` ({ [path] = true }).
function M.refresh(dirs, marks)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if M.is_dired(b) then
      for _, sd in ipairs(M.subdirs(b)) do
        if dirs[sd.path] then
          M.revert(b, { marks = marks })
          break
        end
      end
    end
  end
end

--- Revert if the directories changed on disk behind our back.
function M.maybe_revert(buf)
  if M.is_dired(buf) and not vim.b[buf].dired_wdired and vim.b[buf].dired_sig ~= signature(buf) then
    M.revert(buf)
  end
end

---------------------------------------------------------------- open

function M.find_buffer(dir)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and vim.b[b].dired_dir == dir then
      return b
    end
  end
end

--- Plain (non-dired) buffer already holding this directory path, e.g. from `:e dir`.
local function find_plain_dir_buffer(dir)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and not M.is_dired(b) then
      local name = api.nvim_buf_get_name(b)
      if name ~= '' and util.normalize(name) == dir and vim.bo[b].buftype == '' then
        return b
      end
    end
  end
end

function M.win_setup(win)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = 'nvic'
end

--- Open (or switch to) the dired buffer for `dir`.
--- opts: buf (reuse this buffer), file (put cursor on it), switches, win (false = don't show)
function M.open(dir, opts)
  opts = opts or {}
  dir = util.abs(dir)
  if not util.is_dir(dir) then
    util.err('Not a directory: ' .. dir)
    return nil
  end

  local buf = M.find_buffer(dir)
  local fresh = false
  if not buf then
    fresh = true
    buf = opts.buf or find_plain_dir_buffer(dir)
    if not buf then
      buf = api.nvim_create_buf(true, false)
    end
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'hide'
    vim.bo[buf].swapfile = false
    pcall(api.nvim_buf_set_name, buf, dir)
    vim.b[buf].dired_dir = dir
    vim.b[buf].dired_switches = opts.switches or config.opts.switches
    vim.b[buf].dired_hide_details = config.opts.hide_details
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = 'dired'
  end

  local win
  if opts.win ~= false then
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    M.win_setup(win)
  end

  if fresh then
    M.revert(buf)
    require('dired.keymaps').apply(buf)
    if not opts.file then
      M.goto_first_file(buf, win)
    end
  else
    M.maybe_revert(buf)
  end
  if opts.file and win then
    M.goto_path(buf, util.abs(opts.file), win)
  end
  return buf
end

return M
