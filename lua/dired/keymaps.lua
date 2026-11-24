-- Default key bindings: the emacs dired-mode-map, spelled for vim.
-- Override or disable with `setup({ keys = { [lhs] = 'action' | false } })`.
local config = require('dired.config')

local M = {}

M.defaults = {
  -- movement
  ['n'] = 'next_line',
  ['p'] = 'prev_line',
  ['<C-n>'] = 'next_line',
  ['<C-p>'] = 'prev_line',
  ['<Space>'] = 'next_line',
  ['gg'] = 'goto_top',
  ['<'] = 'prev_dirline',
  ['>'] = 'next_dirline',
  ['<M-{>'] = 'prev_marked',
  ['<M-}>'] = 'next_marked',
  ['*<C-n>'] = 'next_marked',
  ['*<C-p>'] = 'prev_marked',
  ['j'] = 'goto_file',
  ['^'] = 'up_directory',
  ['-'] = 'up_directory', -- extra alias (not in emacs)
  -- visiting
  ['<CR>'] = 'find_file',
  ['f'] = 'find_file',
  ['e'] = 'find_file',
  ['o'] = 'find_file_other_window',
  ['<C-o>'] = 'display_file',
  ['v'] = 'view_file',
  ['a'] = 'find_alternate_file',
  -- marks
  ['m'] = 'mark',
  ['u'] = 'unmark',
  ['d'] = 'flag_delete',
  ['<BS>'] = 'unmark_backward',
  ['<Del>'] = 'unmark_backward',
  ['U'] = 'unmark_all',
  ['<M-BS>'] = 'unmark_all_files',
  ['t'] = 'toggle_marks',
  ['x'] = 'do_flagged_delete',
  ['*m'] = 'mark',
  ['*u'] = 'unmark',
  ['*!'] = 'unmark_all',
  ['*<BS>'] = 'unmark_all',
  ['*?'] = 'unmark_all_files',
  ['**'] = 'mark_executables',
  ['*/'] = 'mark_directories',
  ['*@'] = 'mark_symlinks',
  ['*s'] = 'mark_subdir_files',
  ['*.'] = 'mark_extension',
  ['*c'] = 'change_marks',
  ['*t'] = 'toggle_marks',
  ['*%'] = 'mark_regexp',
  ['%m'] = 'mark_regexp',
  ['%d'] = 'flag_regexp',
  ['%g'] = 'mark_containing',
  ['%&'] = 'flag_garbage',
  ['%u'] = 'upcase',
  ['%l'] = 'downcase',
  ['%R'] = 'rename_regexp',
  ['%C'] = 'copy_regexp',
  ['%H'] = 'hardlink_regexp',
  ['%S'] = 'symlink_regexp',
  ['%Y'] = 'relsymlink_regexp',
  ['~'] = 'flag_backups',
  ['#'] = 'flag_autosave',
  ['.'] = 'clean_directory',
  -- operations
  ['C'] = 'copy',
  ['R'] = 'rename',
  ['D'] = 'delete',
  ['S'] = 'symlink',
  ['Y'] = 'relsymlink',
  ['H'] = 'hardlink',
  ['+'] = 'create_directory',
  ['M'] = 'chmod',
  ['O'] = 'chown',
  ['G'] = 'chgrp',
  ['T'] = 'touch',
  ['Z'] = 'compress',
  ['c'] = 'compress_to',
  ['!'] = 'shell_command',
  ['&'] = 'async_shell_command',
  ['X'] = 'shell_command',
  ['='] = 'diff',
  ['A'] = 'find_regexp',
  ['Q'] = 'query_replace',
  ['L'] = 'load',
  ['w'] = 'copy_filename',
  ['gw'] = 'copy_filename_abs',
  ['y'] = 'show_file_type',
  ['W'] = 'browse_url',
  -- buffer
  ['g'] = 'revert',
  ['l'] = 'redisplay',
  ['s'] = 'sort_toggle',
  ['('] = 'toggle_details',
  ['i'] = 'insert_subdir',
  ['$'] = 'hide_subdir',
  ['<M-$>'] = 'hide_all',
  ['k'] = 'kill_lines',
  ['<C-M-n>'] = 'next_subdir',
  ['<C-M-p>'] = 'prev_subdir',
  ['<C-M-u>'] = 'tree_up',
  ['<C-M-d>'] = 'tree_down',
  ['<C-x><C-q>'] = 'wdired',
  ['q'] = 'quit',
  ['?'] = 'summary',
  ['h'] = 'help',
}

-- oil.nvim's default keymaps, mapped to the closest dired action.
-- (oil: g? select <C-s> <C-h> <C-t> <C-p> <C-c> <C-l> - _ ` g~ gs gx g. g\\)
M.oil = {
  ['g?'] = 'help',
  ['<CR>'] = 'find_file',
  ['<C-s>'] = 'find_file_vsplit',
  ['<C-h>'] = 'find_file_split',
  ['<C-t>'] = 'find_file_tab',
  ['<C-p>'] = 'display_file',
  ['<C-c>'] = 'quit',
  ['<C-l>'] = 'revert',
  ['-'] = 'up_directory',
  ['_'] = 'open_cwd',
  ['`'] = 'cd',
  ['g~'] = 'tcd',
  ['gs'] = 'sort_toggle',
  ['gx'] = 'browse_url',
  ['g.'] = 'toggle_hidden',
  ['g\\'] = 'toggle_trash',
}

-- Vim-flavoured keys for the dired commands, added to the oil preset.
-- Rule of thumb: vim verbs for the common things (c copy, dd delete,
-- a/o add new), `g`-prefix for the rest. None collide with oil's keys.
M.oil_extras = {
  -- marks
  ['<Tab>'] = 'toggle_mark', -- mark / unmark the file, move down
  ['U'] = 'unmark_all',
  ['~'] = 'toggle_marks',
  ['g/'] = 'mark_regexp',
  [']m'] = 'next_marked',
  ['[m'] = 'prev_marked',
  -- everyday file operations
  ['m'] = 'move',
  ['r'] = 'rename_here',
  ['c'] = 'copy',
  ['dd'] = 'delete',
  ['a'] = 'create_file', -- end the name with / for a directory
  ['o'] = 'create_directory',
  ['yp'] = 'copy_filename', -- yank path (name)
  ['yP'] = 'copy_filename_abs', -- yank full path
  ['ge'] = 'wdired', -- edit names in place
  ['i'] = 'insert_subdir',
  -- links, permissions
  ['gl'] = 'symlink',
  ['gr'] = 'relsymlink',
  ['gh'] = 'hardlink',
  ['gm'] = 'chmod',
  ['go'] = 'chown',
  ['gG'] = 'chgrp',
  ['gT'] = 'touch',
  ['gz'] = 'compress',
  ['gZ'] = 'compress_to',
  -- by pattern
  ['gR'] = 'rename_regexp',
  ['gC'] = 'copy_regexp',
  ['gU'] = 'upcase',
  ['gu'] = 'downcase',
  ['gb'] = 'flag_backups',
  ['g&'] = 'flag_garbage',
  -- run things
  ['!'] = 'shell_command',
  ['&'] = 'async_shell_command',
  ['='] = 'diff',
  ['gA'] = 'find_regexp',
  ['gQ'] = 'query_replace',
  -- subdirectories and view
  ['za'] = 'hide_subdir',
  ['zM'] = 'hide_all',
  ['zR'] = 'show_all',
  [']]'] = 'next_subdir',
  ['[['] = 'prev_subdir',
  ['[u'] = 'tree_up',
  [']d'] = 'tree_down',
  ['gK'] = 'kill_lines',
  ['g,'] = 'toggle_details',
}

--- preset + user overrides, `false` entries removed
function M.merged()
  local res
  if config.opts.preset == 'oil' then
    res = vim.deepcopy(config.opts.oil_extras and M.oil_extras or {})
    for lhs, action in pairs(M.oil) do
      res[lhs] = action
    end
  else
    res = vim.deepcopy(M.defaults)
  end
  for lhs, action in pairs(config.opts.keys or {}) do
    res[lhs] = action or nil
  end
  return res
end

local applied = {} -- buf -> { lhs, ... }

function M.apply(buf)
  local actions = require('dired.actions')
  M.clear(buf)
  local lhss = {}
  for lhs, name in pairs(M.merged()) do
    local a = actions.list[name]
    if a then
      vim.keymap.set('n', lhs, function()
        local ok, err = pcall(a.fn)
        if not ok then
          vim.notify('dired: ' .. tostring(err), vim.log.levels.ERROR)
        end
      end, { buffer = buf, silent = true, nowait = false, desc = 'dired: ' .. a.desc })
      lhss[#lhss + 1] = lhs
    end
  end
  applied[buf] = lhss
end

function M.clear(buf)
  for _, lhs in ipairs(applied[buf] or {}) do
    pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
  end
  applied[buf] = nil
end

return M
