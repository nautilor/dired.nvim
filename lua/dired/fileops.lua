-- File operations: C R D S Y H + M O G T Z c  and the % regexp variants.
local buf = require('dired.buf')
local util = require('dired.util')
local config = require('dired.config')

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

---------------------------------------------------------------- low level

local function scan(path)
  local names = {}
  local h = uv.fs_scandir(path)
  if h then
    while true do
      local n = uv.fs_scandir_next(h)
      if not n then
        break
      end
      names[#names + 1] = n
    end
  end
  return names
end

local function copy_tree(src, dst)
  local st = uv.fs_lstat(src)
  if not st then
    return nil, 'No such file: ' .. src
  end
  if st.type == 'link' then
    local target = uv.fs_readlink(src)
    if util.exists(dst) then
      uv.fs_unlink(dst)
    end
    return uv.fs_symlink(target, dst)
  elseif st.type == 'directory' then
    if dst == src or dst:sub(1, #src + 1) == src .. '/' then
      return nil, 'Cannot copy a directory into itself'
    end
    if not util.is_dir(dst) then
      local ok, err = uv.fs_mkdir(dst, st.mode % 4096)
      if not ok then
        return nil, err
      end
    end
    for _, n in ipairs(scan(src)) do
      local ok, err = copy_tree(src .. '/' .. n, dst .. '/' .. n)
      if not ok then
        return nil, err
      end
    end
    if config.opts.copy_preserve_time then
      uv.fs_utime(dst, st.atime.sec, st.mtime.sec)
    end
    return true
  end
  local ok, err = uv.fs_copyfile(src, dst)
  if ok and config.opts.copy_preserve_time then
    uv.fs_utime(dst, st.atime.sec, st.mtime.sec)
  end
  return ok, err
end

local function rm_tree(path)
  local st = uv.fs_lstat(path)
  if not st then
    return true
  end
  if st.type == 'directory' then
    for _, n in ipairs(scan(path)) do
      local ok, err = rm_tree(path .. '/' .. n)
      if not ok then
        return nil, err
      end
    end
    return uv.fs_rmdir(path)
  end
  return uv.fs_unlink(path)
end

local function move_tree(src, dst)
  local ok, err, code = uv.fs_rename(src, dst)
  if ok then
    return true
  end
  if code == 'EXDEV' then
    local ok2, err2 = copy_tree(src, dst)
    if not ok2 then
      return nil, err2
    end
    return rm_tree(src)
  end
  return nil, err
end

local function trash(path)
  for _, cmd in ipairs({ { 'gio', 'trash', '--' }, { 'trash-put', '--' }, { 'trash' } }) do
    if vim.fn.executable(cmd[1]) == 1 then
      local c = vim.list_extend(vim.deepcopy(cmd), { path })
      local res = vim.system(c, { text = true }):wait()
      if res.code == 0 then
        return true
      end
      return nil, res.stderr
    end
  end
  return nil, 'No trash command found (gio / trash-put / trash)'
end

--- Re-point loaded buffers visiting `src` (or below) at `dst`.
local function rename_buffers(src, dst)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == '' then
      local name = api.nvim_buf_get_name(b)
      local new
      if name == src then
        new = dst
      elseif name:sub(1, #src + 1) == src .. '/' then
        new = dst .. name:sub(#src + 1)
      end
      if new then
        pcall(api.nvim_buf_set_name, b, new)
      end
    end
  end
end
M._rename_buffers = rename_buffers

local function same_file(a, b)
  local sa, sb = uv.fs_stat(a), uv.fs_stat(b)
  return sa and sb and sa.ino == sb.ino and sa.dev == sb.dev
end

local function check_dots(files)
  for _, f in ipairs(files) do
    if f.is_dot then
      util.err("Cannot operate on `.' or `..'")
      return false
    end
  end
  return true
end

local function current_dir(b)
  return buf.subdir_at(b, api.nvim_win_get_cursor(0)[1]) or vim.b[b].dired_dir
end

local function describe(files)
  if #files == 1 then
    return files[1].name
  end
  return util.plural(#files, 'file')
end

local function listing_prompt(title, files)
  local lines = { title }
  for i, f in ipairs(files) do
    if i > 15 then
      lines[#lines + 1] = ('  ...and %d more'):format(#files - 15)
      break
    end
    lines[#lines + 1] = '  ' .. f.name
  end
  return table.concat(lines, '\n')
end

---------------------------------------------------------------- generic create-files

--- spec = {
---   name   = 'Copy',
---   fn     = function(src, dst, file) -> ok, err,
---   marker = char | nil,   -- mark given to the new file (`dired-keep-marker-*`)
---   keep   = bool,         -- keep the mark of the original (rename)
---   rename = bool,         -- source disappears
---   copy   = bool,         -- directory sources need `recursive_copies`
--- }
--- dst_for(file) -> absolute destination or nil (skip)
local function perform(b, files, dst_for, spec)
  local ok_n, failures = 0, {}
  local extra, affected = {}, {}
  local all, recursive_ok = false, false
  for _, f in ipairs(files) do
    local dst = dst_for(f)
    local skip = dst == nil
    if not skip then
      if dst == f.path then
        failures[#failures + 1] = ('%s: cannot %s to itself'):format(f.name, spec.name:lower())
        skip = true
      elseif spec.copy and f.type == 'd' and not recursive_ok then
        local pol = config.opts.recursive_copies
        if pol == 'always' or (pol == 'top' and util.yn(('Recursive copies of %s? '):format(f.name))) then
          recursive_ok = true
        else
          failures[#failures + 1] = ('%s: directory not copied'):format(f.name)
          skip = true
        end
      end
    end
    if not skip and util.exists(dst) and not same_file(f.path, dst) and not all then
      local c = util.choose(('File %s already exists; overwrite?'):format(dst), '&Yes\n&No\n&All\n&Quit', 2)
      if c == 3 then
        all = true
      elseif c == 2 then
        skip = true
      elseif c == 4 or c == 0 then
        break
      end
    end
    if not skip then
      local ok, err = spec.fn(f.path, dst, f)
      if ok then
        ok_n = ok_n + 1
        local m = spec.keep and f.mark or spec.marker
        if m and m ~= ' ' then
          extra[dst] = m
        end
        affected[util.dirname(dst)] = true
        affected[f.dir] = true
        if spec.rename then
          rename_buffers(f.path, dst)
        end
      else
        failures[#failures + 1] = ('%s: %s'):format(f.name, tostring(err))
      end
    end
  end
  if #failures == 0 then
    util.msg(('%s: %s'):format(spec.name, util.plural(ok_n, 'file')))
  else
    util.err(('%s: %d of %d failed: %s'):format(spec.name, #failures, #files, table.concat(failures, '; ')))
  end
  buf.refresh(affected, extra)
  return ok_n
end

local function default_target(b, cdir)
  if config.opts.dwim_target then
    local cur = api.nvim_get_current_win()
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if w ~= cur then
        local ob = api.nvim_win_get_buf(w)
        if buf.is_dired(ob) then
          local lnum = api.nvim_win_get_cursor(w)[1]
          return (buf.subdir_at(ob, lnum) or vim.b[ob].dired_dir):gsub('/?$', '/')
        end
      end
    end
  end
  return (cdir:gsub('/?$', '/'))
end

local function ask_target(b, files, spec)
  local cdir = current_dir(b)
  local to = util.ask(('%s %s to: '):format(spec.name, describe(files)), default_target(b, cdir), 'file')
  if not to or to == '' then
    return nil
  end
  return to, cdir
end

local function plain_dst(files, to, cdir)
  local is_dir = to:sub(-1) == '/' or util.is_dir(util.abs(to, cdir))
  local target = util.abs(to, cdir)
  if #files > 1 and not is_dir then
    util.err(('Target %s must be a directory'):format(to))
    return nil
  end
  return function(f)
    if is_dir then
      return util.join(target, util.basename(f.path))
    end
    return target
  end
end

local SPECS = {}

SPECS.copy = {
  name = 'Copy',
  marker = 'C',
  copy = true,
  fn = copy_tree,
}
SPECS.rename = {
  name = 'Move',
  keep = true,
  rename = true,
  fn = move_tree,
}
SPECS.rename_here = {
  name = 'Rename',
  keep = true,
  rename = true,
  fn = move_tree,
}
SPECS.symlink = {
  name = 'Symlink',
  marker = 'S',
  fn = function(src, dst)
    if util.exists(dst) then
      uv.fs_unlink(dst)
    end
    return uv.fs_symlink(src, dst)
  end,
}
SPECS.relsymlink = {
  name = 'RelSymLink',
  marker = 'S',
  fn = function(src, dst)
    if util.exists(dst) then
      uv.fs_unlink(dst)
    end
    return uv.fs_symlink(util.relpath(util.dirname(dst), src), dst)
  end,
}
SPECS.hardlink = {
  name = 'Hardlink',
  marker = 'H',
  fn = function(src, dst)
    if util.exists(dst) then
      uv.fs_unlink(dst)
    end
    return uv.fs_link(src, dst)
  end,
}

local function create(kind)
  return function(b, files)
    if #files == 0 or not check_dots(files) then
      return
    end
    local spec = SPECS[kind]
    local to, cdir = ask_target(b, files, spec)
    if not to then
      return
    end
    local dst_for = plain_dst(files, to, cdir)
    if dst_for then
      perform(b, files, dst_for, spec)
    end
  end
end

--- `r` (oil preset): rename one file in place; several files fall back to move.
function M.rename_here(b, files)
  if #files ~= 1 then
    return M.rename(b, files)
  end
  local f = files[1]
  if not check_dots(files) then
    return
  end
  local to = util.ask(('Rename %s to: '):format(f.name), f.name, 'file')
  if not to or to == '' or to == f.name then
    return
  end
  local dst = util.abs(to, f.dir)
  if util.is_dir(dst) and dst ~= f.path then
    dst = util.join(dst, f.name)
  end
  perform(b, files, function()
    return dst
  end, SPECS.rename_here)
end

M.copy = create('copy')
M.rename = create('rename')
M.symlink = create('symlink')
M.relsymlink = create('relsymlink')
M.hardlink = create('hardlink')

---------------------------------------------------------------- regexp variants

--- % R % C % H % S % Y : `whole` matches the full path (count prefix)
local function create_regexp(kind)
  return function(b, files, whole)
    if #files == 0 or not check_dots(files) then
      return
    end
    local spec = SPECS[kind]
    local from = util.ask(('%s <regexp> from: '):format(spec.name))
    if not from or from == '' then
      return
    end
    local matcher, pat = util.compile(from)
    if not matcher then
      util.err(pat)
      return
    end
    local to = util.ask(('%s <regexp> %s to: '):format(spec.name, from))
    if not to then
      return
    end
    local repl = util.emacs_repl_to_vim(to)
    perform(b, files, function(f)
      local subject = whole and f.path or f.name
      if not matcher(subject) then
        return nil
      end
      local new = vim.fn.substitute(subject, pat, repl, '')
      if new == subject then
        return nil
      end
      return util.abs(new, f.dir)
    end, spec)
  end
end

M.rename_regexp = create_regexp('rename')
M.copy_regexp = create_regexp('copy')
M.hardlink_regexp = create_regexp('hardlink')
M.symlink_regexp = create_regexp('symlink')
M.relsymlink_regexp = create_regexp('relsymlink')

--- % u / % l
local function change_case(fnc)
  return function(b, files)
    if #files == 0 or not check_dots(files) then
      return
    end
    perform(b, files, function(f)
      local new = fnc(f.name)
      if new == f.name then
        return nil
      end
      return util.join(f.dir, new)
    end, SPECS.rename)
  end
end

M.upcase = change_case(string.upper)
M.downcase = change_case(string.lower)

--- Rename a set of {src, dst} pairs atomically-ish (handles swaps). Used by wdired.
function M.rename_pairs(pairs_list)
  local srcs = {}
  for _, p in ipairs(pairs_list) do
    srcs[p[1]] = true
  end
  local tmp = {}
  local n = 0
  for i, p in ipairs(pairs_list) do
    if srcs[p[2]] then
      local t = p[1] .. ('.dired-tmp-%d-%d'):format(uv.os_getpid(), i)
      local ok, err = move_tree(p[1], t)
      if not ok then
        return nil, err
      end
      tmp[i] = t
    end
  end
  for i, p in ipairs(pairs_list) do
    local from = tmp[i] or p[1]
    if util.exists(p[2]) and not same_file(from, p[2]) then
      if not util.yn(('File %s exists; overwrite? '):format(p[2])) then
        goto continue
      end
    end
    do
      local parent = util.dirname(p[2])
      if not util.is_dir(parent) then
        vim.fn.mkdir(parent, 'p')
      end
      local ok, err = move_tree(from, p[2])
      if not ok then
        return nil, err
      end
      rename_buffers(p[1], p[2])
      n = n + 1
    end
    ::continue::
  end
  return n
end

---------------------------------------------------------------- delete

local function is_real_dir(path)
  local st = uv.fs_lstat(path)
  return st ~= nil and st.type == 'directory'
end

local function kill_buffers_of(path)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == '' and api.nvim_buf_get_name(b) == path then
      if util.yn(('Kill buffer of %s, too? '):format(util.basename(path))) then
        pcall(api.nvim_buf_delete, b, { force = true })
      end
    end
  end
end

--- D / x. `files` already selected. `flagged` just changes the wording.
function M.delete(b, files, flagged)
  if #files == 0 or not check_dots(files) then
    return
  end
  local prompt
  if #files == 1 then
    prompt = ('Delete %s? '):format(files[1].name)
  else
    prompt = listing_prompt(('Delete %s?'):format(flagged and util.plural(#files, 'flagged file') or util.plural(#files, 'file')), files)
  end
  if not util.yn(prompt) then
    util.msg('(No deletions performed)')
    return
  end
  local n, fails, affected = 0, {}, {}
  local policy = config.opts.recursive_deletes
  local rec_all = false
  for _, f in ipairs(files) do
    local ok, err = true, nil
    if is_real_dir(f.path) and #scan(f.path) > 0 then
      if policy == 'always' or rec_all then
        -- go
      elseif policy == 'top' then
        if not util.yn(('Recursive delete of %s? '):format(f.name)) then
          ok, err = false, 'not deleted'
        end
      else
        ok, err = false, 'directory not empty'
      end
    end
    if ok then
      if config.opts.delete_by_moving_to_trash then
        ok, err = trash(f.path)
      else
        ok, err = rm_tree(f.path)
      end
    end
    if ok then
      n = n + 1
      affected[f.dir] = true
      kill_buffers_of(f.path)
    else
      fails[#fails + 1] = ('%s: %s'):format(f.name, tostring(err))
    end
  end
  if #fails == 0 then
    util.msg(('Deleted %s'):format(util.plural(n, 'file')))
  else
    util.err(('Deletion failed for %d of %d: %s'):format(#fails, #files, table.concat(fails, '; ')))
  end
  buf.refresh(affected)
end

---------------------------------------------------------------- mkdir

function M.create_directory(b)
  local cdir = current_dir(b)
  local name = util.ask('Create directory: ', cdir .. '/', 'dir')
  if not name or name == '' then
    return
  end
  local full = util.abs(name, cdir)
  if util.exists(full) then
    util.err(('Cannot create directory %s: file exists'):format(full))
    return
  end
  -- first non-existing component = what shows up in a dired listing
  local top = full
  while not util.exists(util.dirname(top)) and util.dirname(top) ~= top do
    top = util.dirname(top)
  end
  local ok, err = pcall(vim.fn.mkdir, full, 'p')
  if not ok then
    util.err(tostring(err))
    return
  end
  buf.refresh({ [util.dirname(top)] = true })
  buf.goto_path(b, top)
end

---------------------------------------------------------------- chmod & friends

local function run(cmd)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if not ok then
    return nil, tostring(res)
  end
  if res.code ~= 0 then
    return nil, (res.stderr or ''):gsub('%s+$', '')
  end
  return true
end

local function chxxx(what, prog)
  return function(b, files)
    if #files == 0 or not check_dots(files) then
      return
    end
    local arg = util.ask(('Change %s of %s to: '):format(what, describe(files)))
    if not arg or arg == '' then
      return
    end
    local cmd = { prog, '--', arg }
    local affected = {}
    for _, f in ipairs(files) do
      cmd[#cmd + 1] = f.path
      affected[f.dir] = true
    end
    local ok, err = run(cmd)
    if not ok then
      util.err(('%s failed: %s'):format(prog, err))
    end
    buf.refresh(affected)
  end
end

M.chmod = chxxx('mode', 'chmod')
M.chown = chxxx('owner', 'chown')
M.chgrp = chxxx('group', 'chgrp')

function M.touch(b, files)
  if #files == 0 or not check_dots(files) then
    return
  end
  local stamp = util.ask(('Change timestamp of %s to (default now; [[CC]YY]MMDDhhmm[.ss]): '):format(describe(files)))
  if stamp == nil then
    return
  end
  local cmd = { 'touch' }
  if stamp ~= '' then
    vim.list_extend(cmd, { '-t', stamp })
  end
  cmd[#cmd + 1] = '--'
  local affected = {}
  for _, f in ipairs(files) do
    cmd[#cmd + 1] = f.path
    affected[f.dir] = true
  end
  local ok, err = run(cmd)
  if not ok then
    util.err('touch failed: ' .. err)
  end
  buf.refresh(affected)
end

---------------------------------------------------------------- compress

local function sh_in(dir, cmd)
  local res = vim.system(cmd, { cwd = dir, text = true }):wait()
  if res.code ~= 0 then
    return nil, (res.stderr or ''):gsub('%s+$', '')
  end
  return true
end

--- Z : (un)compress each file
function M.compress(b, files)
  if #files == 0 or not check_dots(files) then
    return
  end
  local affected, n, fails = {}, 0, {}
  for _, f in ipairs(files) do
    local ok, err
    local name = f.name
    if f.type == 'd' then
      ok, err = sh_in(f.dir, { 'tar', '-czf', name .. '.tar.gz', '--', name })
    elseif name:match('%.tar%.gz$') or name:match('%.tgz$') then
      ok, err = sh_in(f.dir, { 'tar', '-xzf', name })
    elseif name:match('%.tar%.bz2$') then
      ok, err = sh_in(f.dir, { 'tar', '-xjf', name })
    elseif name:match('%.tar%.xz$') then
      ok, err = sh_in(f.dir, { 'tar', '-xJf', name })
    elseif name:match('%.tar%.zst$') then
      ok, err = sh_in(f.dir, { 'tar', '--zstd', '-xf', name })
    elseif name:match('%.zip$') then
      ok, err = sh_in(f.dir, { 'unzip', '-o', name })
    elseif name:match('%.gz$') then
      ok, err = sh_in(f.dir, { 'gunzip', '--', name })
    elseif name:match('%.bz2$') then
      ok, err = sh_in(f.dir, { 'bunzip2', '--', name })
    elseif name:match('%.xz$') then
      ok, err = sh_in(f.dir, { 'unxz', '--', name })
    elseif name:match('%.zst$') then
      ok, err = sh_in(f.dir, { 'unzstd', '--rm', '-q', '--', name })
    else
      ok, err = sh_in(f.dir, { 'gzip', '--', name })
    end
    if ok then
      n = n + 1
      affected[f.dir] = true
    else
      fails[#fails + 1] = name .. ': ' .. tostring(err)
    end
  end
  if #fails > 0 then
    util.err('Compress failed: ' .. table.concat(fails, '; '))
  else
    util.msg(('Compress: %s'):format(util.plural(n, 'file')))
  end
  buf.refresh(affected)
end

local ARCHIVERS = {
  { '%.tar%.gz$', { 'tar', '-czf' } },
  { '%.tgz$', { 'tar', '-czf' } },
  { '%.tar%.bz2$', { 'tar', '-cjf' } },
  { '%.tar%.xz$', { 'tar', '-cJf' } },
  { '%.tar%.zst$', { 'tar', '--zstd', '-cf' } },
  { '%.tar$', { 'tar', '-cf' } },
  { '%.zip$', { 'zip', '-r' } },
  { '%.7z$', { '7z', 'a' } },
}

--- c : compress files into one archive
function M.compress_to(b, files)
  if #files == 0 or not check_dots(files) then
    return
  end
  local cdir = current_dir(b)
  local default = (#files == 1 and files[1].name or util.basename(cdir)) .. '.tar.gz'
  local out = util.ask(('Compress %s to: '):format(describe(files)), cdir .. '/' .. default, 'file')
  if not out or out == '' then
    return
  end
  out = util.abs(out, cdir)
  local cmd
  for _, a in ipairs(ARCHIVERS) do
    if out:match(a[1]) then
      cmd = vim.deepcopy(a[2])
      break
    end
  end
  if not cmd then
    util.err('Unknown archive type (use .tar.gz .tgz .tar.bz2 .tar.xz .tar.zst .tar .zip .7z)')
    return
  end
  if util.exists(out) and not util.yn(('File %s exists; overwrite? '):format(out)) then
    return
  end
  cmd[#cmd + 1] = out
  local affected = { [util.dirname(out)] = true }
  for _, f in ipairs(files) do
    cmd[#cmd + 1] = f.dir == cdir and f.name or f.path
  end
  local ok, err = sh_in(cdir, cmd)
  if not ok then
    util.err('Compress failed: ' .. tostring(err))
  end
  buf.refresh(affected, { [out] = ' ' })
end

return M
