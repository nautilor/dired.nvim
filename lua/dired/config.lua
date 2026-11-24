local M = {}

M.defaults = {
  -- `dired-listing-switches`
  switches = '-al',
  -- take over directory buffers (`nvim .`, `:e some/dir`) like emacs does
  hijack_netrw = true,
  -- `dired-dwim-target`: default copy/rename target = dir of the other visible dired window
  dwim_target = false,
  -- `dired-recursive-copies` / `dired-recursive-deletes`: false | 'top' | 'always'
  recursive_copies = 'top',
  recursive_deletes = 'top',
  -- `delete-by-moving-to-trash`
  delete_by_moving_to_trash = false,
  -- `dired-copy-preserve-time`
  copy_preserve_time = true,
  -- `case-fold-search` for the `% m`, `% d`, `% R` ... regexp commands
  case_fold = true,
  -- `dired-kept-versions` / `kept-old-versions` (used by `.`)
  kept_versions = 2,
  kept_old_versions = 2,
  -- `dired-garbage-files-regexp` (emacs regexp syntax)
  garbage_files_regexp = [[\.\(?:aux\|bak\|dvi\|log\|orig\|rej\|toc\)\']],
  -- `dired-hide-details-mode` initial state
  hide_details = false,
  -- colour the listing columns. true | false | table of toggles:
  -- { permissions, links, owner, group, size, date, filetype }  (filetype = names by kind)
  colors = {
    permissions = true,
    links = true,
    owner = true,
    group = true,
    size = true,
    date = true,
    filetype = true,
  },
  -- key overrides: { [lhs] = 'action_name' | false }
  keys = {},
}

M.opts = vim.deepcopy(M.defaults)

--- Effective colour toggles as a table (handles `colors = true/false`).
function M.colors()
  local c = M.opts.colors
  if type(c) == 'table' then
    return c
  end
  local on = c ~= false
  return { permissions = on, links = on, owner = on, group = on, size = on, date = on, filetype = on }
end

function M.setup(o)
  M.opts = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), o or {})
end

return M
