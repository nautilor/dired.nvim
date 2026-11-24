# dired.nvim

Emacs `dired` for Neovim, in Lua. Same buffer layout (`ls -al` listing with a mark
column, subdirectories inserted into the same buffer), same keys, same semantics
(marked files, else current file, else next N files with a count).
Prefer neovim-like keys? There is an [oil.nvim style preset](#oil-keys) too.

Requires Neovim >= 0.10 (developed on 0.12), a Unix `ls` (GNU or BSD), Linux/macOS.

## Try it without touching your config

```sh
dev/run.sh                      # throwaway sandbox tree, isolated nvim (NVIM_APPNAME=dired-dev)
dev/run.sh --keep               # keep the sandbox afterwards
dev/run.sh ~/some/dir           # real directory (operations are real!)
DIRED_PRESET=oil dev/run.sh     # try the oil.nvim key preset
```

Inside that nvim: `:DiredReload` reloads the plugin code after you edit it, `-` is
`dired-jump` outside dired, `<space>d` opens dired on the cwd.

Tests: `nvim --headless -u NONE -l tests/run.lua`

## lazy.nvim (later)

```lua
{
  dir = '~/Sources/PERSONAL/dired.nvim',   -- or the git url once pushed
  lazy = false,                            -- needed for directory hijacking at startup
  opts = {},                               -- e.g. { preset = 'oil' }
  keys = { { '-', '<Cmd>DiredJump<CR>', desc = 'dired-jump' } },
}
```

## Open dired for `nvim /path/` and `nvim .`

On by default (`hijack_netrw = true`): directory buffers (`nvim dir`, `nvim .`, `:e dir`) open as dired,
and netrw is switched off. The only requirement is that the plugin loads at startup, so with
lazy.nvim use `lazy = false` (a lazy-loaded plugin would start too late for `nvim dir`):

```lua
{ dir = '~/Sources/PERSONAL/dired.nvim', lazy = false, opts = {} }
```

Set `hijack_netrw = false` to keep netrw and only use `:Dired`.

## Commands

`:Dired [dir]`, `:DiredJump` (= `dired-jump`, cursor lands on the current file).
Lua: `require('dired').open(dir)`, `require('dired').jump()`.

## Keys

Two key sets ship with the plugin. Pick one with `preset` (default `emacs`) and learn it in steps:

| Preset | For | Section |
|--------|-----|---------|
| `'emacs'` (default) | the real dired keys, 1:1 | [Emacs keys](#emacs-keys-default) |
| `'oil'` | neovim-like keys, the same as oil.nvim | [Oil keys](#oil-keys) |

Choose it in `setup` (or lazy's `opts`):

```lua
opts = {
  preset = 'emacs',     -- 'emacs' (default) | 'oil'
  oil_extras = true,    -- only with preset = 'oil': also bind the vim-style file commands
                        -- (false = just oil's own 16 keys)
  keys = {},            -- any preset: { [lhs] = 'action' | false } to add, change or remove keys
}
```

Press `h` (emacs) or `g?` (oil) inside a dired buffer for the live list.
Whatever the preset, `keys = { [lhs] = 'action' | false }` adds, changes or removes single keys.

### Emacs keys (default)

Step 1 is enough to browse; each next step adds power.
A number before a key (`3m`) means "do it for the next 3 files".
Keys written with a space between them (`% m`) are typed without it (`%m`).
`?` shows a one-line reminder.

#### 1. Get around

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

#### 2. Mark files

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

#### 3. Manage files

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

#### 4. Pick files with patterns

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

Add a count to match the full path instead of just the name (`1 % m`).

#### 5. Run things

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

#### 6. Subdirectories in one buffer

| Key | Does |
|-----|------|
| `i` | insert a subdirectory listing below (on a directory line, that directory) |
| `$` | hide / show this subdirectory |
| `M-$` | hide / show all |
| `k` | remove lines from the buffer (files stay); on a subdirectory header removes the whole listing |
| `C-M-n` / `C-M-p` | next / previous subdirectory |
| `C-M-u` / `C-M-d` | up to the parent / down to a child subdirectory listing |

#### 7. View options

| Key | Does |
|-----|------|
| `s` | switch sorting between name and date (with a count: edit the `ls` switches) |
| `(` | hide / show details (permissions, owner, size, date) |

#### 8. Edit names like text (wdired)

`C-x C-q` makes the file names editable. Change them with any vim command, then
`:w` (or `C-c C-c`) to rename for real, or `C-c C-k` to cancel.

### Emacs keys vs vim keys

Keeping the emacs keys means `j`, `k`, `g`, `G`, `s`, `h` and `l` are dired commands in these buffers.
`g` is refresh, so `gg` has its own binding but other `g…` commands are shadowed.
Rebind or disable any key:

```lua
opts = { keys = { j = false, k = false, ['<leader>j'] = 'goto_file', ['<leader>k'] = 'kill_lines' } }
```

Action names are in `lua/dired/actions.lua` (`def('name', ...)`) and shown by `h`.

### Oil keys

`preset = 'oil'` replaces the emacs keys with oil.nvim's default keymaps, so `j`, `k`, `gg`, `s`, ... are plain vim again:

```lua
opts = { preset = 'oil' }
```

| Key | Does |
|-----|------|
| `g?` | show key help |
| `<CR>` | open file / enter directory |
| `<C-s>` / `<C-h>` / `<C-t>` | open in vertical split / horizontal split / new tab |
| `<C-p>` | preview in the other window (focus stays) |
| `<C-c>` | close |
| `<C-l>` | refresh |
| `-` | parent directory |
| `_` | open dired on the cwd |
| `` ` `` / `g~` | `:cd` / `:tcd` to this directory |
| `gs` | toggle sort (name / date) |
| `gx` | open with the system app |
| `g.` | show / hide dotfiles |
| `g\` | open the trash directory |

#### Oil preset: dired commands with vim-style keys

On top of oil's keys the preset binds the dired commands to keys that read like vim.
Everyday things get single keys (`<Tab>` `m` `r` `c` `a` `o` `dd`), the rest live under `g`. None of them collide with oil's keys.
Like in the emacs preset, commands work on marked files, else the file under the cursor
(a count, `3c`, means the next 3 files).

| Key | Does | Vim idea |
|-----|------|----------|
| `<Tab>` | mark / unmark the file, move down | |
| `q` / `<Esc>` | close dired | |
| `U` / `~` | unmark all / toggle all marks | |
| `g/` | mark by name regexp | like `:g/` |
| `]m` / `[m` | next / previous marked file | |
| `m` | **m**ove (asks for the target directory) | |
| `r` | **r**ename in place (several files: move) | |
| `c` | **c**opy | |
| `dd` | delete | **d**elete |
| `a` | **a**dd a file; end the name with `/` for a directory (`a/b/` creates both) | **a**ppend |
| `o` | new directory | **o**pen new |
| `yp` / `yP` | copy the file name / full path to the clipboard | **y**ank **p**ath |
| `ge` | edit names in place (wdired), `:w` applies | |
| `i` | insert a subdirectory listing | **i**nsert |
| `gl` / `gr` / `gh` | symlink / relative symlink / hard link | **l**ink, **r**elative, **h**ard |
| `gm` / `go` / `gG` / `gT` | chmod / chown / chgrp / touch | **m**ode, **o**wner, **G**roup, **T**ime |
| `gz` / `gZ` | compress each / compress into one archive | **z**ip |
| `gR` / `gC` | rename / copy by regexp (`\1`, `\&`) | |
| `gU` / `gu` | upper / lower-case names | same as vim's `gU` / `gu` |
| `gb` / `g&` | flag backup files / garbage files for deletion | |
| `!` / `&` | shell command / in the background | same as vim's `!` |
| `=` | diff against another file | |
| `gA` / `gQ` | regexp search / replace in marked files | |
| `za` / `zM` / `zR` | hide-show this subdirectory / hide all / show all | folds |
| `]]` / `[[` | next / previous subdirectory | |
| `[u` / `]d` | up to the parent / down to a child subdirectory listing | |
| `gK` | remove lines from the buffer (files stay) | |
| `g,` | hide / show details | |

Want only oil's own keys? Set `oil_extras = false`.
Want different keys? `keys = { ['<leader>r'] = 'rename', c = false }` on top of the preset.

Differences from oil: dired is not an editable buffer (use `ge` to rename
by editing names), `gs` toggles name/date instead of asking, and `g.` toggles `ls -a`.

> Shadowed Neovim keys in these buffers: `<Tab>` (= `<C-i>`, jump forward), `gr` (= the `grr`/`grn`/... LSP
> defaults of Neovim 0.11+), `ge`, `gh`, and the edit keys `m r c a o`. Dired buffers are read-only,
> so nothing useful is lost. Set `oil_extras = false` or override with `keys` if it bothers you.

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
| `preset` | `'emacs'` | `'emacs'` or `'oil'`, see [Keys](#keys) |
| `oil_extras` | `true` | with `preset = 'oil'`: also bind the vim-style dired commands |
| `keys` | `{}` | key overrides on top of the preset |

Highlight groups (all `default` links, override them in your colorscheme):

- names: `DiredHeader` `DiredDirectory` `DiredSymlink` `DiredExecutable` `DiredSpecial` (devices, sockets, pipes)
- marks: `DiredMark` `DiredMarked` `DiredFlagged` `DiredFlagMark`
- columns: `DiredPermType` `DiredPermRead` `DiredPermWrite` `DiredPermExec` `DiredPermNone` `DiredLinks` `DiredOwner` `DiredGroup` `DiredSize` `DiredDate`

## Not implemented (no sensible nvim equivalent)

`B` byte-compile, `P` print, `N` man, image-dired, `dired-omit-mode`, `M-s` incremental
filename search, remote (TRAMP) directories, and editing permissions/symlink targets in wdired.
`!` shell output goes to a split instead of the echo area when longer than one line;
`=` shows a unified diff in a scratch buffer.
