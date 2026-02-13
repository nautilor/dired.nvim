# Read me first

**This plugin is being generated with the help of Claude just to see what it was capable of. The plugin works but is not fully featured yet. It's more of a proof of concept than a production-ready plugin. I created it to try to quickly visualize an ideal file explorer for me and i'm currently using it**

# nvim-dired

A file manager for Neovim inspired by Emacs Dired.

## Features

* `ls -l`-style interface
* Fullscreen toggle with `<leader>e`
* Multiple file selection
* Copy/move operations
* Create/delete/rename files and directories
* Intuitive Vim-style navigation

## Installation

### With lazy.nvim

```lua
{
  'nautilor/dired.nvim',
  config = function()
    require('dired').setup()
  end
}
```

### With packer.nvim

```lua
use {
  'nautilor/dired.nvim',
  config = function()
    require('dired').setup()
  end
}
```

## Commands

* `:Dired` – Open/close Dired

## Keybindings

### Open/Close

* `<leader>e` – Toggle Dired window
* `<Esc>` or `q` – Close Dired and return to the previous buffer

### Navigation

* `j` / `k` or `↓` / `↑` – Move cursor up/down
* `<Enter>` – Enter a directory or open a file
* `<Left>` – Go to parent directory

### Selection

* `<Tab>` – Select/deselect current file (supports multiple selection)

### File Operations

#### Copy/Move

* `x` – Mark files/directories for **move** (cut)

  * If files are selected, marks all selected
  * Otherwise marks only the current file
* `y` – Mark files/directories for **copy**

  * If files are selected, marks all selected
  * Otherwise marks only the current file
* `p` – Paste (copy or move) marked files into the current directory

#### Create

* `a` – Create a new file or directory

  * If the name ends with `/`, a directory is created
  * Otherwise, a file is created

#### Delete

* `d` – Delete files/directories

  * If files are selected, deletes all selected
  * Otherwise deletes the current file
  * Shows confirmation with default `Y` (press Enter to confirm)

#### Rename

* `r` – Rename the current file/directory

## Interface

The interface displays:

```
  /current/path/directory

  * [X] drwxr-xr-x     4.0K Jan 15 10:30 folder/
      -rw-r--r--     1.2K Jan 15 09:45 file.txt
  *     -rw-r--r--   125.5K Jan 14 18:22 image.png
```

Legend:

* `*` – File selected for multiple operations
* `[X]` – File marked for move (cut)
* `[C]` – File marked for copy
* Permissions – As in `ls -l`
* Size – Formatted (B, K, M, G)
* Date/Time – Last modified
* Name – With trailing `/` for directories

## Typical Workflow

### Move files

1. Navigate to the file to move
2. Press `x` (or select multiple files with `<Tab>` and then `x`)
3. Navigate to the destination directory
4. Press `p` to move

### Copy files

1. Navigate to the file to copy
2. Press `y` (or select multiple files with `<Tab>` and then `y`)
3. Navigate to the destination directory
4. Press `p` to copy

### Delete multiple files

1. Select files with `<Tab>`
2. Press `d` and confirm with `Y` or `Enter`

## Custom Configuration

```lua
require('dired').setup({
  -- Future options
})

-- Customize the keybinding
vim.keymap.set('n', '<leader>d', require('dired').toggle,
  { noremap = true, silent = true, desc = 'Toggle Dired' })
```

## License

MIT

