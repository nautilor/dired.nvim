-- Syntax highlighting for Dired buffer
if vim.b.did_ftplugin then
	return
end
vim.b.did_ftplugin = 1

-- Highlight groups (ls -l --color style)
vim.api.nvim_set_hl(0, 'DiredDirectory', { fg = '#5FAFFF', bold = true })
vim.api.nvim_set_hl(0, 'DiredExecutable', { fg = '#5FFF5F', bold = true })
vim.api.nvim_set_hl(0, 'DiredSelected', { fg = '#FFFF5F', bold = true })
vim.api.nvim_set_hl(0, 'DiredMarked', { fg = '#FF5F5F', bold = true })
vim.api.nvim_set_hl(0, 'DiredPath', { fg = '#5FFFFF', italic = true })
vim.api.nvim_set_hl(0, 'DiredCursorLine', { bg = '#2A2A2A' })
vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#2A2A2A' })

-- Set cursorline highlight
vim.wo.cursorline = true
vim.wo.cursorlineopt = 'both'
