-- `ls` driver and parser. Buffer layout is the same as emacs dired:
--
--   /abs/dir:
--   total used in directory 48 available 120.3 GiB
--   drwxr-xr-x  2 me me 4096 Nov 24 10:00 .
--   ...
--
-- every line is prefixed by two columns: the mark column and a space.

local M = {}

local gnu

local function is_gnu()
  if gnu == nil then
    local ok, res = pcall(function()
      return vim.system({ 'ls', '--version' }, { text = true }):wait()
    end)
    gnu = ok and res.code == 0 and (res.stdout or ''):find('GNU', 1, true) ~= nil
  end
  return gnu
end

-- Dates must be parseable: force C locale for time only.
local function env()
  local e = { LC_TIME = 'C' }
  local all = vim.env.LC_ALL
  if all and all ~= '' then
    e.LC_ALL = ''
    e.LC_COLLATE = all
    e.LC_CTYPE = all
    e.LC_MESSAGES = all
  end
  return e
end

function M.ls(dir, switches)
  local cmd = { 'ls' }
  for sw in switches:gmatch('%S+') do
    cmd[#cmd + 1] = sw
  end
  if is_gnu() then
    cmd[#cmd + 1] = '--quoting-style=literal'
  end
  cmd[#cmd + 1] = '.'
  local ok, res = pcall(function()
    return vim.system(cmd, { cwd = dir, text = true, env = env() }):wait()
  end)
  if not ok then
    return nil, tostring(res)
  end
  if res.code ~= 0 and (res.stdout or '') == '' then
    return nil, (res.stderr or 'ls failed'):gsub('\n$', '')
  end
  return res.stdout or ''
end

local function human(kb)
  local units = { 'KiB', 'MiB', 'GiB', 'TiB', 'PiB' }
  local v, i = kb, 1
  while v >= 1024 and i < #units do
    v = v / 1024
    i = i + 1
  end
  return ('%.1f %s'):format(v, units[i])
end

local function free_space(dir)
  local ok, res = pcall(function()
    return vim.system({ 'df', '-Pk', dir }, { text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    return '?'
  end
  local line = vim.split(res.stdout or '', '\n', { plain = true })[2]
  local kb = line and tonumber(line:match('^%S+%s+%S+%s+%S+%s+(%d+)'))
  return kb and human(kb) or '?'
end

--- Lines (with mark column) for one directory, header included.
function M.render(dir, switches)
  local lines = { '  ' .. dir .. ':' }
  local out, err = M.ls(dir, switches)
  if not out then
    for l in vim.gsplit(err, '\n', { plain = true, trimempty = true }) do
      lines[#lines + 1] = '  ' .. l
    end
    return lines
  end
  local first = true
  for _, l in ipairs(vim.split(out, '\n', { plain = true, trimempty = true })) do
    local total = first and l:match('^total (%S+)$')
    first = false
    if total then
      l = ('total used in directory %s available %s'):format(total, free_space(dir))
    end
    lines[#lines + 1] = '  ' .. l
  end
  return lines
end

local TYPES = '[-dlcbpsDwCMnP?]'
local PERMS = '[-rwxsStTlL?+.@]+'

--- Parse a file line. Returns nil if the line is not a file entry.
--- { mark, type, perms, name, col (1-based byte col of name), link, is_dot }
function M.parse(line)
  local mark = line:match('^(.) [%s%d]*' .. TYPES .. PERMS .. ' +%d+ ')
  if not mark then
    return nil
  end
  local perms = line:match('^. [%s%d]*(' .. TYPES .. PERMS .. ')')
  local ds, e = line:find('%s%a%a%a%s+%d+%s+[%d:]+%s', 3)
  if not e then
    return nil
  end
  local name = line:sub(e + 1)
  local link
  if perms:sub(1, 1) == 'l' then
    local n, t = name:match('^(.-) %-> (.*)$')
    if n then
      name, link = n, t
    end
  end
  return {
    mark = mark,
    type = perms:sub(1, 1),
    perms = perms,
    name = name,
    col = e + 1,
    date_range = { ds, e - 1 }, -- 0-based start, exclusive end
    link = link,
    is_dot = name == '.' or name == '..',
  }
end

--- Byte ranges (0-based start, exclusive end) of the columns of a parsed line:
--- { perms, links, owner, group, size, date }. Used for colouring.
function M.fields(line, info)
  local _, pe = line:find('^. [%s%d]*' .. TYPES .. PERMS)
  if not pe then
    return nil
  end
  local ps = line:find(TYPES, 3)
  local res = { perms = { ps - 1, pe } }
  local middle = line:sub(pe + 1, info.date_range[1] - 1)
  local toks = {}
  for a, t, z in middle:gmatch('()(%S+)()') do
    toks[#toks + 1] = { pe + a - 1, pe + z - 1, t }
  end
  if #toks == 4 then
    for i, k in ipairs({ 'links', 'owner', 'group', 'size' }) do
      res[k] = { toks[i][1], toks[i][2] }
    end
  end
  res.date = { info.date_range[1], info.date_range[2] }
  return res
end

return M
