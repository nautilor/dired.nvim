-- Syntax highlighting for Dired buffer
if vim.b.did_ftplugin then
	return
end
vim.b.did_ftplugin = 1

-- Highlight groups
vim.cmd([[
  highlight DiredDirectory ctermfg=Blue guifg=#569CD6 gui=bold
  highlight DiredExecutable ctermfg=Green guifg=#4EC9B0
  highlight DiredSelected ctermfg=Yellow guifg=#DCDCAA gui=bold
  highlight DiredMarked ctermfg=Red guifg=#F48771 gui=bold
  highlight DiredPath ctermfg=Cyan guifg=#4FC1FF gui=italic
  highlight DiredCursorLine guibg=#2D2D30 ctermbg=237
]])

-- Apply syntax matching
vim.cmd([[
  syntax clear
  syntax match DiredDirectory /\/\s*$/
  syntax match DiredExecutable /^.\{-}x.\{-}\s\+\zs.\+$/
  syntax match DiredSelected /^\*\s/
  syntax match DiredMarked /\[X\]\|\[C\]/
  syntax match DiredPath /^\s\+\/.\+$/
]])

-- Set cursorline highlight
vim.wo.cursorline = true
vim.wo.cursorlineopt = 'both'
