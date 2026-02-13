-- nvim-dired plugin entry point
if vim.g.loaded_nvim_dired then
	return
end
vim.g.loaded_nvim_dired = 1

-- Load the main module
require('dired').setup()
