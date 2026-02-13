-- Syntax highlighting for Dired buffer
if vim.b.did_ftplugin then
	return
end
vim.b.did_ftplugin = 1

-- Highlight groups (ls -l --color style)
vim.api.nvim_set_hl(0, 'DiredDirectory', { fg = '#7aa2f7', bold = true })
vim.api.nvim_set_hl(0, 'DiredExecutable', { fg = '#73daca', bold = true })
vim.api.nvim_set_hl(0, 'DiredSelected', { fg = '#e0af68', bold = true })
vim.api.nvim_set_hl(0, 'DiredMarked', { fg = '#f7768e', bold = true })
vim.api.nvim_set_hl(0, 'DiredPath', { fg = '#7dcfff', italic = true })
vim.api.nvim_set_hl(0, 'DiredCursorLine', { bg = '#323750' })
vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#323750' })

-- Set cursorline highlight
-- vim.wo.cursorline = true
-- vim.wo.cursorlineopt = 'both'
