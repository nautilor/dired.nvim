# dired.nvim

Emacs `dired` for Neovim, in Lua. Same buffer layout (`ls -al` listing with a mark
column, subdirectories inserted into the same buffer), same keys, same semantics
(marked files, else current file, else next N files with a count).

Requires Neovim >= 0.10 (developed on 0.12), a Unix `ls` (GNU or BSD), Linux/macOS.

## Try it without touching your config

```sh
dev/run.sh            # throwaway sandbox tree, isolated nvim (NVIM_APPNAME=dired-dev)
dev/run.sh --keep     # keep the sandbox afterwards
dev/run.sh ~/some/dir # real directory (operations are real!)
```

Inside that nvim: `:DiredReload` reloads the plugin code after you edit it, `-` is
`dired-jump`, `<space>d` opens dired on the cwd.

Tests: `nvim --headless -u NONE -l tests/run.lua`

## lazy.nvim (later)

```lua
{
  dir = '~/Sources/PERSONAL/dired.nvim',   -- or the git url once pushed
  lazy = false,                            -- needed for directory hijacking at startup
  opts = {},
  keys = { { '-', '<Cmd>DiredJump<CR>', desc = 'dired-jump' } },
}
```

## Commands

`:Dired [dir]`, `:DiredJump` (= `dired-jump`, cursor lands on the current file).
Lua: `require('dired').open(dir)`, `require('dired').jump()`.

## Keys

Learn it in steps. Step 1 is enough to browse; each next step adds power.
Keys are the emacs dired ones. A number before a key (`3m`) means "do it for the next 3 files".
Keys written with a space between them (`% m`) are typed without it (`%m`). Press `h` in a dired buffer for the full list, `?` for a one-line reminder.

### 1. Get around

| Key | Does |
|-----|------|
| `n` / `p` (or `C-n` / `C-p`, `SPC`) | next / previous line |
| `RET` (or `f`, `e`) | open file, or enter directory |
| `^` (or `-`) | go up to the parent directory |
| `o` | open in the other window |
| `C-o` | show file in the other window, keep focus here |
| `v` | open read-only |
| `a` | open and replace the dired buffer |
| `j` | jump to a file by name |
| `<` / `>` | previous / next directory line |
| `g` | refresh the listing (marks are kept) |
| `q` | quit |

### 2. Mark files

Most commands work on **marked** files; with no marks they work on the file under the cursor.

| Key | Does |
|-----|------|
| `m` / `u` | mark / unmark (then move down) |
| `DEL` | unmark and move up |
| `U` | remove all marks |
| `t` | toggle: marked becomes unmarked and the reverse |
| `M-{` / `M-}` | previous / next marked file |
| `* /` | mark all directories |
| `* @` | mark all symlinks |
| `* *` | mark all executables |
| `* .` | mark by extension |
| `* s` | mark everything in this subdirectory |
| `* c` | change one kind of mark into another |

### 3. Manage files

| Key | Does |
|-----|------|
| `C` | copy (copied files get a `C` mark) |
| `R` | rename / move |
| `D` | delete (asks first) |
| `+` | create a directory |
| `S` / `Y` / `H` | absolute symlink / relative symlink / hard link |
| `M` / `O` / `G` | chmod / chown / chgrp |
| `T` | touch (set timestamp) |
| `Z` | compress or uncompress |
| `c` | compress marked files into one archive |

Safer delete, emacs style: press `d` on files to *flag* them (shown as `D`), look over the list, then `x` deletes all flagged files.

### 4. Pick files with patterns

Patterns are emacs regexps (case-insensitive by default).

| Key | Does |
|-----|------|
| `% m` | mark files whose name matches |
| `% d` | flag matching files for deletion |
| `% g` | mark files whose *contents* match |
| `% R` / `% C` | rename / copy by pattern (`\1`, `\&` in the new name) |
| `% H` / `% S` / `% Y` | hard link / symlink / relative symlink by pattern |
| `% u` / `% l` | upper / lower-case the names |
| `~` | flag backup files (`foo~`) |
| `#` | flag autosave files (`#foo#`) |
| `.` | flag old numbered backups (`foo.~3~`) |
| `% &` | flag garbage files (`.log`, `.bak`, `.orig`...) |

Add a count to match the full path instead of just the name (`1% m`, typed without the space).

### 5. Run things

| Key | Does |
|-----|------|
| `!` | shell command on the files |
| `&` | same, but in the background |
| `=` | diff the current file against another |
| `A` | search marked files for a regexp (results in quickfix) |
| `Q` | regexp search and replace in marked files |
| `L` | `:source` the file |
| `w` | copy file name (`gw` for the full path) |
| `y` | show file type |
| `W` | open with the system app |

Shell command rules: `*` in the command is replaced by all the files at once, `?` runs it once per file, with neither the command runs once per file with the name appended.

### 6. Subdirectories in one buffer

| Key | Does |
|-----|------|
| `i` | insert a subdirectory listing below (on a directory line, that directory) |
| `$` | hide / show this subdirectory |
| `M-$` | hide / show all |
| `k` | remove lines from the buffer (files stay); on a subdirectory header removes the whole listing |
| `C-M-n` / `C-M-p` | next / previous subdirectory |
| `C-M-u` / `C-M-d` | up to the parent / down to a child subdirectory listing |

### 7. View options

| Key | Does |
|-----|------|
| `s` | switch sorting between name and date (with a count: edit the `ls` switches) |
| `(` | hide / show details (permissions, owner, size, date) |

### 8. Edit names like text (wdired)

`C-x C-q` makes the file names editable. Change them with any vim command, then
`C-c C-c` to rename for real or `C-c C-k` to cancel.

### Key conflicts with vim

Keeping the emacs keys means `j`, `k`, `g`, `G`, `s`, `h` and `l` are dired commands in these buffers.
`g` is refresh, so `gg` has its own binding but other `g…` commands are shadowed.
Rebind or disable any key:

```lua
opts = { keys = { j = false, k = false, ['<leader>j'] = 'goto_file', ['<leader>k'] = 'kill_lines' } }
```

Action names are in `lua/dired/actions.lua` (`def('name', ...)`) and shown by `h`.

## Options (`setup{}`)

| option | default | emacs variable |
|--------|---------|----------------|
| `switches` | `'-al'` | `dired-listing-switches` |
| `hijack_netrw` | `true` | `nvim dir` / `:e dir` open dired |
| `dwim_target` | `false` | `dired-dwim-target` |
| `recursive_copies` | `'top'` | `dired-recursive-copies` (`false`/`'top'`/`'always'`) |
| `recursive_deletes` | `'top'` | `dired-recursive-deletes` |
| `delete_by_moving_to_trash` | `false` | `delete-by-moving-to-trash` (gio/trash-put/trash) |
| `copy_preserve_time` | `true` | `dired-copy-preserve-time` |
| `case_fold` | `true` | `case-fold-search` |
| `kept_versions`, `kept_old_versions` | `2`, `2` | `dired-kept-versions`, `kept-old-versions` |
| `garbage_files_regexp` | aux/bak/dvi/log/orig/rej/toc | `dired-garbage-files-regexp` |
| `hide_details` | `false` | `dired-hide-details-mode` |
| `colors` | all on | colour listing columns: `true`/`false`, or `{ permissions, links, owner, group, size, date, filetype }` toggles (`colors = { owner = false }` turns just that one off) |
| `keys` | `{}` | key overrides |

Highlight groups (all `default` links, override them in your colorscheme):

- names: `DiredHeader` `DiredDirectory` `DiredSymlink` `DiredExecutable` `DiredSpecial` (devices, sockets, pipes)
- marks: `DiredMark` `DiredMarked` `DiredFlagged` `DiredFlagMark`
- columns: `DiredPermType` `DiredPermRead` `DiredPermWrite` `DiredPermExec` `DiredPermNone` `DiredLinks` `DiredOwner` `DiredGroup` `DiredSize` `DiredDate`

## Not implemented (no sensible nvim equivalent)

`B` byte-compile, `P` print, `N` man, image-dired, `dired-omit-mode`, `M-s` incremental
filename search, remote (TRAMP) directories, and editing permissions/symlink targets in wdired.
`!` shell output goes to a split instead of the echo area when longer than one line;
`=` shows a unified diff in a scratch buffer.
