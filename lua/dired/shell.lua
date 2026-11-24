-- ! & = A Q : shell commands, diff, search, replace over marked files
local buf = require('dired.buf')
local util = require('dired.util')
local config = require('dired.config')

local api = vim.api

local M = {}

local function current_dir(b)
  return buf.subdir_at(b, api.nvim_win_get_cursor(0)[1]) or vim.b[b].dired_dir
end

local function describe(files)
  if #files == 1 then
    return files[1].name
  end
  return util.plural(#files, 'file')
end

--- Show text in a scratch window at the bottom (`*Shell Command Output*`).
function M.show_output(name, text, ft)
  local lines = vim.split((text or ''):gsub('\n$', ''), '\n', { plain = true })
  if #lines == 1 and lines[1] == '' then
    util.msg('(Shell command succeeded with no output)')
    return
  end
  if #lines == 1 and ft == nil then
    util.msg(lines[1])
    return
  end
  local b
  for _, x in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(x):match(vim.pesc(name) .. '$') then
      b = x
    end
  end
  if not b then
    b = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(b, name)
  end
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modified = false
  vim.bo[b].buftype = 'nofile'
  vim.bo[b].bufhidden = 'wipe'
  vim.bo[b].filetype = ft or ''
  local shown = false
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) == b then
      shown = true
    end
  end
  if not shown then
    vim.cmd('botright split')
    api.nvim_win_set_buf(0, b)
    api.nvim_win_set_height(0, math.min(#lines + 1, 15))
  end
  vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = b, silent = true })
end

local function rel(f, cwd)
  return f.dir == cwd and f.name or f.path
end

--- Build the list of command lines per dired-do-shell-command rules.
function M.build_commands(cmd, files, cwd)
  local esc = {}
  for i, f in ipairs(files) do
    esc[i] = vim.fn.shellescape(rel(f, cwd))
  end
  local padded = ' ' .. cmd .. ' '
  if padded:find('%s%*%s') then
    local all = table.concat(esc, ' ')
    local out = padded:gsub('(%s)%*(%s)', function(a, c)
      return a .. all .. c
    end)
    return { vim.trim(out) }
  elseif padded:find('%s%?%s') then
    local res = {}
    for i = 1, #files do
      local out = padded:gsub('(%s)%?(%s)', function(a, c)
        return a .. esc[i] .. c
      end)
      res[#res + 1] = vim.trim(out)
    end
    return res
  end
  local res = {}
  for i = 1, #files do
    res[#res + 1] = cmd .. ' ' .. esc[i]
  end
  return res
end

--- `!` and `&`
function M.shell_command(b, files, async)
  if #files == 0 then
    return
  end
  local cwd = current_dir(b)
  local cmd = util.ask(('%s on %s: '):format(async and '&' or '!', describe(files)), '', 'shellcmd')
  if not cmd or vim.trim(cmd) == '' then
    return
  end
  if cmd:match('&%s*$') then
    async = true
    cmd = cmd:gsub('%s*&%s*$', '')
  end
  local cmds = M.build_commands(cmd, files, cwd)
  if async then
    for _, c in ipairs(cmds) do
      vim.system({ 'sh', '-c', c }, { cwd = cwd, text = true }, function(res)
        vim.schedule(function()
          M.show_output('*Async Shell Command*', (res.stdout or '') .. (res.stderr or ''))
          buf.revert(b)
        end)
      end)
    end
    return
  end
  local out = {}
  for _, c in ipairs(cmds) do
    local res = vim.system({ 'sh', '-c', c }, { cwd = cwd, text = true }):wait()
    out[#out + 1] = (res.stdout or '') .. (res.stderr or '')
  end
  M.show_output('*Shell Command Output*', table.concat(out))
  if api.nvim_buf_is_valid(b) then
    buf.revert(b)
  end
end

--- `=` : diff current file with another
function M.diff(b)
  local cur = buf.file_at(b, api.nvim_win_get_cursor(0)[1])
  if not cur then
    util.err('No file on this line')
    return
  end
  local default
  local marked = buf.get_marked(b, nil, '*')
  for _, m in ipairs(marked) do
    if m.path ~= cur.path then
      default = m.path
      break
    end
  end
  local other = util.ask(('Diff %s with: '):format(cur.name), default or (cur.dir .. '/'), 'file')
  if not other or other == '' then
    return
  end
  other = util.abs(other, cur.dir)
  local res = vim.system({ 'diff', '-u', '--', cur.path, other }, { text = true }):wait()
  if res.code == 0 then
    util.msg('No differences found')
  elseif res.code == 1 then
    M.show_output('*Diff*', res.stdout, 'diff')
  else
    util.err(res.stderr or 'diff failed')
  end
end

local function paths(files)
  return vim.tbl_map(function(f)
    return vim.fn.fnameescape(f.path)
  end, files)
end

--- `A` : regexp search in marked files, results in quickfix
function M.find_regexp(b, files)
  files = vim.tbl_filter(function(f)
    return f.type ~= 'd'
  end, files)
  if #files == 0 then
    return
  end
  local re = util.ask('Search marked files (regexp): ')
  if not re or re == '' then
    return
  end
  local matcher, pat = util.compile(re)
  if not matcher then
    util.err(pat)
    return
  end
  local ok = pcall(vim.cmd, ('silent vimgrep /%s/gj %s'):format(pat:gsub('/', '\\/'), table.concat(paths(files), ' ')))
  if ok and #vim.fn.getqflist() > 0 then
    vim.cmd('copen')
  else
    util.msg('No matches')
  end
end

--- `Q` : query-replace-regexp in marked files
function M.query_replace(b, files)
  files = vim.tbl_filter(function(f)
    return f.type ~= 'd'
  end, files)
  if #files == 0 then
    return
  end
  local from = util.ask('Query replace regexp in marked files: ')
  if not from or from == '' then
    return
  end
  local matcher, pat = util.compile(from)
  if not matcher then
    util.err(pat)
    return
  end
  local to = util.ask(('Query replace %s with: '):format(from))
  if not to then
    return
  end
  local repl = util.emacs_repl_to_vim(to):gsub('/', '\\/')
  vim.cmd('args ' .. table.concat(paths(files), ' '))
  local ok, err = pcall(vim.cmd, ('argdo %%s/%s/%s/gce | update'):format(pat:gsub('/', '\\/'), repl))
  if not ok then
    util.err(tostring(err))
  end
end

return M
