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
]])

-- Apply syntax highlighting
vim.cmd([[
  syntax match DiredDirectory /\/$/
  syntax match DiredExecutable /^.\{-}x.\{-} \zs.\+$/
  syntax match DiredSelected /^\* /
  syntax match DiredMarked /\[X\]\|\[C\]/
  syntax match DiredPath /^  \/.\+/
]])
