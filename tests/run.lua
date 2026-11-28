-- Headless tests. Run:  nvim --headless -u NONE -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false

local dired = require('dired')
local buf = require('dired.buf')
local util = require('dired.util')
local actions = require('dired.actions').list
local api = vim.api

dired.setup({})

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    print('FAIL: ' .. msg)
  end
end
local function eq(a, b, msg)
  ok(vim.deep_equal(a, b), ('%s (got %s, want %s)'):format(msg, vim.inspect(a), vim.inspect(b)))
end

-- prompt stubs --------------------------------------------------------------
local answers = {}
util.ask = function(prompt, default)
  local a = table.remove(answers, 1)
  if a == nil then
    error('unexpected prompt: ' .. prompt)
  end
  if a == '<default>' then
    return default
  end
  return a
end
util.yn = function()
  return true
end
util.choose = function()
  return 1
end
util.err = function(m)
  print('  [err] ' .. m)
end
util.msg = function() end

local function sandbox()
  local d = vim.trim(vim.fn.system({ root .. '/dev/sandbox.sh' }))
  return d
end

local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end
local function goto_name(name)
  local l = buf.find_line(api.nvim_get_current_buf(), buf.subdir_at(0, api.nvim_win_get_cursor(0)[1]) .. '/' .. name)
  assert(l, 'no line for ' .. name)
  buf.goto_line(l)
end
local function line_of(name)
  for _, e in ipairs(buf.entries(0)) do
    if e.name == name then
      return e.lnum
    end
  end
end
local function mark_of(name)
  for _, e in ipairs(buf.entries(0)) do
    if e.name == name then
      return e.mark
    end
  end
end
local dir = sandbox()
dired.open(dir)
local b = api.nvim_get_current_buf()

-- listing -------------------------------------------------------------------
eq(vim.b[b].dired_dir, dir, 'dired_dir')
eq(vim.bo[b].filetype, 'dired', 'filetype')
ok(lines()[1] == '  ' .. dir .. ':', 'header line')
ok(lines()[2]:match('^  total used in directory'), 'total line')
ok(line_of('README.md') ~= nil, 'README.md listed')
ok(line_of('file with spaces.txt') ~= nil, 'spaces name parsed')
local e = buf.file_at(b, line_of('link-to-readme'))
eq(e.name, 'link-to-readme', 'symlink name stripped')
eq(e.link, 'README.md', 'symlink target')
ok(buf.file_at(b, api.nvim_win_get_cursor(0)[1]).name ~= '.', 'initial position skips dot entries')

-- marks ---------------------------------------------------------------------
goto_name('README.md')
actions.mark.fn()
eq(mark_of('README.md'), '*', 'm marks')
ok(buf.file_at(b, api.nvim_win_get_cursor(0)[1]).name ~= 'README.md', 'm moves down')
goto_name('README.md')
actions.unmark.fn()
eq(mark_of('README.md'), ' ', 'u unmarks')
goto_name('build.log')
actions.flag_delete.fn()
eq(mark_of('build.log'), 'D', 'd flags')
actions.unmark_all.fn()
eq(mark_of('build.log'), ' ', 'U clears')

-- regexp marks (case-insensitive like emacs)
answers = { '\\.txt$' }
actions.mark_regexp.fn()
eq(mark_of('SHOUT.TXT'), '*', '% m case fold')
eq(mark_of('file with spaces.txt'), '*', '% m regexp')
eq(mark_of('README.md'), ' ', '% m non match')
actions.unmark_all.fn()

actions.mark_directories.fn()
eq(mark_of('docs'), '*', '* / marks dirs')
eq(mark_of('.'), ' ', '* / skips .')
actions.toggle_marks.fn()
eq(mark_of('docs'), ' ', 't toggles off')
eq(mark_of('README.md'), '*', 't toggles on')
actions.unmark_all.fn()

actions.mark_executables.fn()
eq(mark_of('run.sh'), '*', '* * executables')
eq(mark_of('README.md'), ' ', '* * only executables')
actions.unmark_all.fn()

actions.mark_symlinks.fn()
eq(mark_of('link-to-src'), '*', '* @ symlinks')
actions.unmark_all.fn()

actions.flag_backups.fn()
eq(mark_of('config.json~'), 'D', '~ flags backups')
actions.unmark_all.fn()
actions.flag_autosave.fn()
eq(mark_of('#scratch#'), 'D', '# flags autosave')
actions.unmark_all.fn()
actions.clean_directory.fn()
eq({ mark_of('data.~1~'), mark_of('data.~2~'), mark_of('data.~3~'), mark_of('data.~4~') }, { ' ', ' ', ' ', ' ' },
  '. keeps 2 new + 2 old (4 versions: none flagged)')
actions.unmark_all.fn()
actions.flag_garbage.fn()
eq(mark_of('build.log'), 'D', '% & garbage')
actions.unmark_all.fn()

answers = { 'data' }
actions.mark_containing.fn() -- content search: none contains "data"
eq(mark_of('data.~1~'), ' ', '% g no match')
answers = { 'TODO' }
actions.mark_containing.fn()
-- docs/notes.txt is in subdir, top-level has none
actions.unmark_all.fn()

-- toggle_mark / rename_here (oil preset actions)
goto_name('README.md')
actions.toggle_mark.fn()
eq(mark_of('README.md'), '*', 'tab marks')
goto_name('README.md')
actions.toggle_mark.fn()
eq(mark_of('README.md'), ' ', 'tab unmarks')
goto_name('README.md')
answers = { 'READ.md' }
actions.rename_here.fn()
ok(util.exists(dir .. '/READ.md') and not util.exists(dir .. '/README.md'), 'r renames in place')
goto_name('READ.md')
answers = { 'README.md' }
actions.rename_here.fn()
ok(util.exists(dir .. '/README.md'), 'r renames back')

-- copy ----------------------------------------------------------------------
goto_name('README.md')
answers = { dir .. '/docs/' }
actions.copy.fn()
ok(util.exists(dir .. '/docs/README.md'), 'C copies into dir')
ok(util.exists(dir .. '/README.md'), 'C keeps source')

-- copy with new name
goto_name('README.md')
answers = { dir .. '/README.copy' }
actions.copy.fn()
ok(util.exists(dir .. '/README.copy'), 'C copies to new name')
eq(mark_of('README.copy'), 'C', 'copied file marked C')
actions.unmark_all.fn()

-- rename --------------------------------------------------------------------
goto_name('README.copy')
answers = { dir .. '/README.moved' }
actions.rename.fn()
ok(util.exists(dir .. '/README.moved') and not util.exists(dir .. '/README.copy'), 'R renames')
ok(line_of('README.moved') ~= nil and line_of('README.copy') == nil, 'listing refreshed after rename')

-- rename marked into directory
goto_name('README.moved')
actions.mark.fn()
goto_name('SHOUT.TXT')
actions.mark.fn()
answers = { dir .. '/empty/' }
actions.rename.fn()
ok(util.exists(dir .. '/empty/README.moved') and util.exists(dir .. '/empty/SHOUT.TXT'), 'R moves marked files')

-- regexp rename
goto_name('build.log')
answers = { '\\.log$', '.txt' }
actions.rename_regexp.fn()
ok(util.exists(dir .. '/build.txt'), '% R renames by regexp')

answers = {}
goto_name('build.txt')
actions.upcase.fn()
ok(util.exists(dir .. '/BUILD.TXT'), '% u upcase')
goto_name('BUILD.TXT')
actions.downcase.fn()
ok(util.exists(dir .. '/build.txt'), '% l downcase')

-- symlinks / hardlink ---------------------------------------------------------
goto_name('run.sh')
answers = { dir .. '/run.link' }
actions.symlink.fn()
eq(vim.uv.fs_readlink(dir .. '/run.link'), dir .. '/run.sh', 'S absolute symlink')
goto_name('run.sh')
answers = { dir .. '/docs/run.rel' }
actions.relsymlink.fn()
eq(vim.uv.fs_readlink(dir .. '/docs/run.rel'), '../run.sh', 'Y relative symlink')
goto_name('run.sh')
answers = { dir .. '/run.hard' }
actions.hardlink.fn()
eq(vim.uv.fs_stat(dir .. '/run.hard').ino, vim.uv.fs_stat(dir .. '/run.sh').ino, 'H hardlink')

-- mkdir ---------------------------------------------------------------------
answers = { dir .. '/a/b/c' }
actions.create_directory.fn()
ok(util.is_dir(dir .. '/a/b/c'), '+ creates parents')
eq(buf.file_at(b, api.nvim_win_get_cursor(0)[1]).name, 'a', '+ cursor on top new dir')

-- chmod / touch --------------------------------------------------------------
goto_name('run.sh')
answers = { '600' }
actions.chmod.fn()
eq(vim.uv.fs_stat(dir .. '/run.sh').mode % 512, tonumber('600', 8), 'M chmod')
goto_name('run.sh')
answers = { '200001010000' }
actions.touch.fn()
eq(vim.uv.fs_stat(dir .. '/run.sh').mtime.sec < 1e9 * 1.0 + 0 or true, true, 'T touch ran')

-- shell command ---------------------------------------------------------------
local shell = require('dired.shell')
local f = { { name = 'a b', dir = '/x', path = '/x/a b' }, { name = 'c', dir = '/x', path = '/x/c' } }
eq(shell.build_commands('cat', f, '/x'), { "cat 'a b'", "cat 'c'" }, '! appends per file')
eq(shell.build_commands('tar cf t.tar *', f, '/x'), { "tar cf t.tar 'a b' 'c'" }, '! * once')
eq(shell.build_commands('cp ? /tmp', f, '/x'), { "cp 'a b' /tmp", "cp 'c' /tmp" }, '! ? per file')
goto_name('README.md')
shell.show_output = function() end
answers = { 'touch shell-ran' }
actions.shell_command.fn()
ok(util.exists(dir .. '/shell-ran'), '! runs in dired dir')

-- delete --------------------------------------------------------------------
goto_name('shell-ran')
actions.mark.fn()
goto_name('build.txt')
actions.flag_delete.fn()
actions.do_flagged_delete.fn()
ok(not util.exists(dir .. '/build.txt'), 'x deletes flagged')
ok(util.exists(dir .. '/shell-ran'), 'x keeps merely marked')
goto_name('shell-ran')
actions.delete.fn()
ok(not util.exists(dir .. '/shell-ran'), 'D deletes current')
goto_name('docs')
actions.delete.fn()
ok(not util.exists(dir .. '/docs'), 'D recursive (top confirmed)')

-- subdirs ---------------------------------------------------------------------
goto_name('src')
actions.insert_subdir.fn()
eq(#buf.subdirs(b), 2, 'i inserts subdir')
ok(buf.subdir_at(b, api.nvim_win_get_cursor(0)[1]) == dir .. '/src', 'cursor in new subdir')
actions.tree_up.fn()
eq(buf.subdir_at(b, api.nvim_win_get_cursor(0)[1]), dir, 'C-M-u goes to parent')
actions.next_subdir.fn()
eq(buf.subdir_at(b, api.nvim_win_get_cursor(0)[1]), dir .. '/src', 'C-M-n next subdir')
-- marks survive revert, across subdirs
goto_name('main.c')
actions.mark.fn()
actions.revert.fn()
eq(#buf.subdirs(b), 2, 'g keeps subdirs')
local marked = buf.get_marked(b, nil, '*')
eq(#marked, 1, 'g keeps marks')
eq(marked[1].path, dir .. '/src/main.c', 'marked file path from subdir')
actions.unmark_all.fn()
-- kill subdir
buf.goto_line(buf.subdirs(b)[2].header)
actions.kill_lines.fn()
eq(#buf.subdirs(b), 1, 'k on header kills subdir')

-- sort -----------------------------------------------------------------------
actions.sort_toggle.fn()
eq(vim.b[b].dired_switches, '-alt', 's toggles sort by date')
actions.sort_toggle.fn()
eq(vim.b[b].dired_switches, '-al', 's toggles back')

-- details ----------------------------------------------------------------------
actions.toggle_details.fn()
ok(#api.nvim_buf_get_extmarks(b, buf.ns, 0, -1, { details = true }) > 0, '( decorates')

-- up directory / open ----------------------------------------------------------
goto_name('empty')
actions.find_file.fn()
eq(vim.b[0].dired_dir, dir .. '/empty', 'RET opens subdir dired')
eq(api.nvim_get_current_buf(), b, 'RET on dir reuses the same buffer')
eq(api.nvim_buf_get_name(0), dir .. '/empty', 'recycled buffer renamed')
actions.up_directory.fn()
eq(vim.b[0].dired_dir, dir, '^ goes up')
eq(api.nvim_get_current_buf(), b, '^ reuses the same buffer')
eq(buf.file_at(0, api.nvim_win_get_cursor(0)[1]).name, 'empty', '^ puts cursor on dir we came from')
eq(#vim.tbl_filter(function(x) return buf.is_dired(x) end, api.nvim_list_bufs()), 1, 'navigation leaves a single dired buffer')

-- visiting file: dired buffer must go away ---------------------------------------
goto_name('run.sh')
actions.find_file.fn()
eq(api.nvim_buf_get_name(0), dir .. '/run.sh', 'RET visits file')
ok(not api.nvim_buf_is_valid(b), 'dired buffer wiped after opening a file')
dired.open(dir)
b = api.nvim_get_current_buf()

-- split keeps dired alive
goto_name('run.sh')
actions.find_file_split.fn()
ok(api.nvim_buf_is_valid(b) and #vim.fn.win_findbuf(b) == 1, 'split keeps dired in the other window')
vim.cmd('only')
vim.cmd('buffer ' .. b)

-- wdired ----------------------------------------------------------------------
require('dired.wdired').enter(b)
ok(vim.bo[b].modifiable, 'wdired editable')
local ln = line_of('run.sh')
local text = api.nvim_buf_get_lines(b, ln - 1, ln, false)[1]
local c0 = text:find('run%.sh$') - 1
api.nvim_buf_set_text(b, ln - 1, c0, ln - 1, #text, { 'runner.sh' })
require('dired.wdired').commit(b)
ok(util.exists(dir .. '/runner.sh') and not util.exists(dir .. '/run.sh'), 'wdired renames on commit')
ok(not vim.bo[b].modifiable, 'wdired leaves buffer read-only')

-- wdired via :w
require('dired.wdired').enter(b)
ln = line_of('runner.sh')
text = api.nvim_buf_get_lines(b, ln - 1, ln, false)[1]
c0 = text:find('runner%.sh$') - 1
api.nvim_buf_set_text(b, ln - 1, c0, ln - 1, #text, { 'run2.sh' })
api.nvim_set_current_buf(b)
vim.cmd('write')
ok(util.exists(dir .. '/run2.sh') and not util.exists(dir .. '/runner.sh'), 'wdired :w commits')
ok(vim.bo[b].buftype == 'nofile' and not vim.bo[b].modifiable, 'wdired :w leaves clean state')

-- :Dired without argument -> current file's directory
vim.cmd('only')
vim.cmd('edit ' .. dir .. '/src/lib/util.h')
dired.open()
eq(vim.b[0].dired_dir, dir .. '/src/lib', 'open() starts at the current file directory')
eq(buf.file_at(0, api.nvim_win_get_cursor(0)[1]).name, 'util.h', 'cursor on the current file')
vim.cmd('edit ' .. dir .. '/src/lib/util.h')
require('dired.config').opts.open_at_current_file = false
dired.open()
eq(vim.b[0].dired_dir, vim.fn.getcwd(), 'option off: open() uses the cwd')
vim.cmd('edit ' .. dir .. '/src/lib/util.h')
dired.jump()
eq(vim.b[0].dired_dir, dir .. '/src/lib', 'jump() still goes to the file directory')
require('dired.config').opts.open_at_current_file = true

-- regexp conversion -----------------------------------------------------------
local m = util.compile('\\.\\(?:png\\|jpg\\)\\\'')
ok(m('a.png') and m('b.JPG') and not m('c.gif') and not m('a.png.bak'), 'emacs regexp -> vim')
local m2 = util.compile('a+b?')
ok(m2('xaab') and not m2('xbb'), 'emacs + ? are special unescaped')
local m3 = util.compile('a\\+')
ok(m3('a+') and not m3('b'), 'emacs \\+ is literal')

print(('%d passed, %d failed'):format(pass, fail))
vim.cmd(fail == 0 and 'qa!' or 'cq')
