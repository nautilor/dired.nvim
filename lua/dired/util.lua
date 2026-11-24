local M = {}
local uv = vim.uv or vim.loop

local CANCEL = '\1dired-cancel\1'

---------------------------------------------------------------- paths

function M.normalize(p)
  return (vim.fs.normalize(p, { expand_env = false }))
end

--- Absolute, normalized (no trailing slash, no `.`/`..`) path.
function M.abs(p, base)
  p = M.normalize(p)
  if p:sub(1, 1) ~= '/' then
    p = M.normalize((base or vim.fn.getcwd()) .. '/' .. p)
  end
  return p
end

function M.join(dir, name)
  if dir == '/' then
    return '/' .. name
  end
  return dir .. '/' .. name
end

function M.dirname(p)
  return vim.fs.dirname(p) or '/'
end

function M.basename(p)
  return vim.fs.basename(p)
end

function M.exists(p)
  return uv.fs_lstat(p) ~= nil
end

function M.is_dir(p)
  local st = uv.fs_stat(p)
  return st ~= nil and st.type == 'directory'
end

function M.relpath(from, to)
  local a = vim.split(from, '/', { plain = true, trimempty = true })
  local b = vim.split(to, '/', { plain = true, trimempty = true })
  local i = 1
  while i <= #a and i <= #b and a[i] == b[i] do
    i = i + 1
  end
  local parts = {}
  for _ = i, #a do
    parts[#parts + 1] = '..'
  end
  for j = i, #b do
    parts[#parts + 1] = b[j]
  end
  if #parts == 0 then
    return '.'
  end
  return table.concat(parts, '/')
end

---------------------------------------------------------------- messages / prompts
-- All interactive input goes through these so tests can stub them.

function M.msg(text)
  vim.api.nvim_echo({ { text } }, false, {})
end

function M.err(text)
  vim.notify(text, vim.log.levels.ERROR)
end

--- Minibuffer-like prompt. Returns nil when cancelled.
function M.ask(prompt, default, completion)
  local ok, res = pcall(vim.fn.input, {
    prompt = prompt,
    default = default or '',
    completion = completion,
    cancelreturn = CANCEL,
  })
  vim.cmd('redraw')
  if not ok or res == CANCEL then
    return nil
  end
  return res
end

--- Pick one of `choices` ("&Yes\n&No"); returns index (0 = aborted).
function M.choose(msg, choices, default)
  return vim.fn.confirm(msg, choices, default or 1)
end

function M.yn(msg)
  return M.choose(msg, '&Yes\n&No', 2) == 1
end

function M.plural(n, word)
  return ('%d %s%s'):format(n, word, n == 1 and '' or 's')
end

---------------------------------------------------------------- emacs regexp -> vim regexp

--- Translate an emacs regexp into a vim (magic) pattern.
function M.emacs_to_vim(re)
  local out, i, n = {}, 1, #re
  local function push(s)
    out[#out + 1] = s
  end
  while i <= n do
    local c = re:sub(i, i)
    if c == '\\' then
      local d = re:sub(i + 1, i + 1)
      i = i + 2
      if d == '(' then
        if re:sub(i, i + 1) == '?:' then
          push('\\%(')
          i = i + 2
        else
          push('\\(')
        end
      elseif d == '+' or d == '?' then
        push(d)
      elseif d == '`' then
        push('\\%^')
      elseif d == "'" then
        push('\\%$')
      elseif d == 'b' then
        push('\\%(\\<\\|\\>\\)')
      elseif (d == 's' or d == 'S') and re:sub(i, i) == '-' then
        push('\\' .. d)
        i = i + 1
      elseif d == '' then
        push('\\\\')
      else
        push('\\' .. d)
      end
    elseif c == '+' or c == '?' or c == '~' then
      push('\\' .. c)
      i = i + 1
    elseif c == '[' then
      local j = i + 1
      if re:sub(j, j) == '^' then
        j = j + 1
      end
      if re:sub(j, j) == ']' then
        j = j + 1
      end
      while j <= n and re:sub(j, j) ~= ']' do
        if re:sub(j, j + 1) == '[:' then
          local e = re:find(':]', j + 2, true)
          j = e and (e + 2) or (j + 1)
        else
          j = j + 1
        end
      end
      push((re:sub(i, j):gsub('\\', '\\\\')))
      i = j + 1
    else
      push(c)
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Translate an emacs replacement string (`\&`, `\1`) into a vim one.
function M.emacs_repl_to_vim(rep)
  local out, i = {}, 1
  while i <= #rep do
    local c = rep:sub(i, i)
    if c == '\\' then
      local d = rep:sub(i + 1, i + 1)
      i = i + 2
      if d == '&' then
        out[#out + 1] = '&'
      elseif d:match('%d') then
        out[#out + 1] = '\\' .. d
      elseif d == '\\' then
        out[#out + 1] = '\\\\'
      else
        out[#out + 1] = d
      end
    elseif c == '&' or c == '~' then
      out[#out + 1] = '\\' .. c
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Compile an emacs regexp. Returns matcher(str)->bool, vimpattern  (or nil, err)
function M.compile(re)
  local case_fold = require('dired.config').opts.case_fold
  local pat = (case_fold and '\\c' or '\\C') .. M.emacs_to_vim(re)
  local ok, rx = pcall(vim.regex, pat)
  if not ok then
    return nil, 'Invalid regexp: ' .. re
  end
  return function(s)
    return rx:match_str(s) ~= nil
  end, pat
end

return M
