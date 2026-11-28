-- Directory completion relative to a base directory (the dired dir you are in).
local util = require('dired.util')
local uv = vim.uv or vim.loop

local M = {}

--- Base directory for the next completion (set by whoever opens the prompt).
M.base = nil

local function base()
  if M.base then
    return M.base
  end
  if require('dired.buf').is_dired(0) then
    return vim.b.dired_dir
  end
  return vim.fn.getcwd()
end

--- Candidates for `lead`, keeping the way it was typed (`../li` -> `../lib/`).
--- Directories first (with a trailing slash); `with_files` adds regular files.
function M.candidates(lead, root, with_files)
  root = root or base()
  local dirpart, partial = lead:match('^(.*/)(.*)$')
  if not dirpart then
    dirpart, partial = '', lead
  end
  local parent
  if dirpart == '' then
    parent = root
  elseif dirpart:sub(1, 1) == '/' or dirpart:sub(1, 1) == '~' then
    parent = util.abs(dirpart)
  else
    parent = util.abs(dirpart, root)
  end
  local res, files = {}, {}
  local h = uv.fs_scandir(parent)
  while h do
    local name, typ = uv.fs_scandir_next(h)
    if not name then
      break
    end
    local is_dir = typ == 'directory'
    if typ == 'link' then
      is_dir = util.is_dir(parent .. '/' .. name)
    end
    local show = partial:sub(1, 1) == '.' or name:sub(1, 1) ~= '.'
    if show and name:sub(1, #partial) == partial then
      if is_dir then
        res[#res + 1] = dirpart .. name .. '/'
      elseif with_files then
        files[#files + 1] = dirpart .. name
      end
    end
  end
  table.sort(res)
  table.sort(files)
  if partial:sub(1, 1) == '.' and ('..'):sub(1, #partial) == partial then
    table.insert(res, 1, dirpart .. '../')
  end
  vim.list_extend(res, files)
  return res
end

-- used as `customlist,v:lua.__dired_complete_paths`
_G.__dired_complete_paths = function(lead)
  return M.candidates(lead, nil, true)
end

--- prompt completion: directories and files
M.cmdline = 'customlist,v:lua.__dired_complete_paths'

--- While a path prompt is open, <CR> on a directory picked from the completion menu only
--- *accepts* it (the prompt stays open), so the next <Tab> lists what is inside.
--- <CR> on a file, or with no menu open, submits as usual. Tab keeps cycling the matches.
function M.with_tab_descend(fn)
  vim.keymap.set('c', '<CR>', function()
    if vim.fn.pumvisible() == 1 and vim.fn.getcmdline():sub(-1) == '/' then
      return vim.api.nvim_replace_termcodes('<C-y>', true, false, true)
    end
    return vim.api.nvim_replace_termcodes('<CR>', true, false, true)
  end, { expr = true, desc = 'dired: <CR> accepts the selected directory' })
  local ok, res = pcall(fn)
  pcall(vim.keymap.del, 'c', '<CR>')
  if not ok then
    error(res, 0)
  end
  return res
end

return M
