-- nvim-dired: A Dired-like file manager for Neovim
-- Main module

local M = {}

-- State
local state = {
	buf = nil,
	win = nil,
	previous_buf = nil,
	previous_win = nil,
	previous_cursorline = nil,
	previous_wrap = nil,
	previous_number = nil,
	previous_relativenumber = nil,
	previous_cursorlineopt = nil,
	current_dir = vim.fn.getcwd(),
	selected_files = {},
	marked_files = {},
	mark_operation = nil, -- 'cut' or 'copy'
	entries = {},
	ns_id = vim.api.nvim_create_namespace('dired_highlight'),
}

-- Utility functions
local function get_file_info(path)
	local stat = vim.loop.fs_stat(path)
	if not stat then
		return nil
	end

	return {
		path = path,
		name = vim.fn.fnamemodify(path, ':t'),
		type = stat.type,
		size = stat.size,
		mtime = stat.mtime.sec,
		mode = stat.mode,
	}
end

local function format_size(size)
	if size < 1024 then
		return string.format("%dB", size)
	elseif size < 1024 * 1024 then
		return string.format("%.1fK", size / 1024)
	elseif size < 1024 * 1024 * 1024 then
		return string.format("%.1fM", size / (1024 * 1024))
	else
		return string.format("%.1fG", size / (1024 * 1024 * 1024))
	end
end

local function format_permissions(mode)
	local perms = {
		(mode % 2 == 1) and 'x' or '-',
		(math.floor(mode / 2) % 2 == 1) and 'w' or '-',
		(math.floor(mode / 4) % 2 == 1) and 'r' or '-',
		(math.floor(mode / 8) % 2 == 1) and 'x' or '-',
		(math.floor(mode / 16) % 2 == 1) and 'w' or '-',
		(math.floor(mode / 32) % 2 == 1) and 'r' or '-',
		(math.floor(mode / 64) % 2 == 1) and 'x' or '-',
		(math.floor(mode / 128) % 2 == 1) and 'w' or '-',
		(math.floor(mode / 256) % 2 == 1) and 'r' or '-',
	}
	return table.concat({ perms[9], perms[8], perms[7], perms[6], perms[5], perms[4], perms[3], perms[2], perms[1] })
end

local function format_time(timestamp)
	return os.date("%b %d %H:%M", timestamp)
end

-- Update buffer paths when files are moved or renamed
local function update_buffer_paths(old_path, new_path)
	-- Get all loaded buffers
	local buffers = vim.api.nvim_list_bufs()

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local buf_name = vim.api.nvim_buf_get_name(buf)

			if buf_name ~= '' then
				-- Check if buffer is the moved file or inside moved directory
				if buf_name == old_path then
					-- Exact match - file was moved/renamed
					vim.api.nvim_buf_set_name(buf, new_path)
				elseif vim.startswith(buf_name, old_path .. '/') then
					-- Buffer is inside a moved directory
					local relative = buf_name:sub(#old_path + 2)
					local new_buf_path = new_path .. '/' .. relative
					vim.api.nvim_buf_set_name(buf, new_buf_path)
				end
			end
		end
	end
end

local function scan_directory(dir)
	local entries = {}

	-- Add parent directory
	if dir ~= '/' then
		table.insert(entries, {
			path = vim.fn.fnamemodify(dir, ':h'),
			name = '..',
			type = 'directory',
			is_parent = true,
		})
	end

	local handle = vim.loop.fs_scandir(dir)
	if not handle then
		return entries
	end

	local dirs = {}
	local files = {}

	while true do
		local name, ftype = vim.loop.fs_scandir_next(handle)
		if not name then break end

		local path = dir .. '/' .. name
		local info = get_file_info(path)

		if info then
			if info.type == 'directory' then
				table.insert(dirs, info)
			else
				table.insert(files, info)
			end
		end
	end

	-- Sort directories and files alphabetically
	table.sort(dirs, function(a, b) return a.name < b.name end)
	table.sort(files, function(a, b) return a.name < b.name end)

	-- Add directories first, then files
	for _, entry in ipairs(dirs) do
		table.insert(entries, entry)
	end
	for _, entry in ipairs(files) do
		table.insert(entries, entry)
	end

	return entries
end

local function render_directory()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	-- Save cursor position before rendering
	local saved_cursor = nil
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		saved_cursor = vim.api.nvim_win_get_cursor(state.win)
	end

	vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(state.buf, state.ns_id, 0, -1)

	state.entries = scan_directory(state.current_dir)
	local lines = {}

	-- Header
	table.insert(lines, '  ' .. state.current_dir)
	table.insert(lines, '')

	-- Entries
	for i, entry in ipairs(state.entries) do
		local line = ''

		-- Selection marker
		local is_selected = vim.tbl_contains(state.selected_files, entry.path)
		line = is_selected and '* ' or '  '

		-- Mark indicator (cut/copy)
		local is_marked = false
		for _, marked in ipairs(state.marked_files) do
			if marked.path == entry.path then
				is_marked = true
				break
			end
		end
		if is_marked then
			line = line .. (state.mark_operation == 'cut' and '[X] ' or '[C] ')
		else
			line = line .. '    '
		end

		if entry.is_parent then
			line = line .. 'drwxr-xr-x         ../'
		else
			-- Permissions
			local perms = entry.type == 'directory' and 'd' or '-'
			perms = perms .. format_permissions(entry.mode or 0)
			line = line .. perms .. ' '

			-- Size
			if entry.type == 'directory' then
				line = line .. string.format("%8s ", '')
			else
				line = line .. string.format("%8s ", format_size(entry.size))
			end

			-- Time
			line = line .. format_time(entry.mtime) .. ' '

			-- Name
			local name = entry.name
			if entry.type == 'directory' then
				name = name .. '/'
			end
			line = line .. name
		end

		table.insert(lines, line)
	end

	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

	-- Apply highlights
	-- Highlight header path
	vim.api.nvim_buf_add_highlight(state.buf, state.ns_id, 'DiredPath', 0, 0, -1)

	-- Highlight entries
	for i, entry in ipairs(state.entries) do
		local line_num = i + 1 -- +2 for header, -1 for 0-based indexing
		local line = lines[line_num + 1]

		-- Highlight selection marker
		local is_selected = vim.tbl_contains(state.selected_files, entry.path)
		if is_selected then
			vim.api.nvim_buf_add_highlight(state.buf, state.ns_id, 'DiredSelected', line_num, 0, 1)
		end

		-- Highlight mark indicator
		local is_marked = false
		for _, marked in ipairs(state.marked_files) do
			if marked.path == entry.path then
				is_marked = true
				break
			end
		end
		if is_marked then
			vim.api.nvim_buf_add_highlight(state.buf, state.ns_id, 'DiredMarked', line_num, 2, 6)
		end

		-- Find where the filename starts
		local name_start = line:find(entry.name or '%.%.')
		if name_start then
			-- Highlight directories
			if entry.type == 'directory' or entry.is_parent then
				vim.api.nvim_buf_add_highlight(state.buf, state.ns_id, 'DiredDirectory', line_num, name_start - 1, -1)
			else
				-- Check if executable
				local perms = format_permissions(entry.mode or 0)
				if perms:match('x') then
					vim.api.nvim_buf_add_highlight(state.buf, state.ns_id, 'DiredExecutable', line_num, name_start - 1, -1)
				end
			end
		end
	end

	vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)

	-- Restore cursor position or set to first entry
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		if saved_cursor then
			-- Make sure cursor is within valid range
			local max_line = vim.api.nvim_buf_line_count(state.buf)
			local target_line = math.min(saved_cursor[1], max_line)
			target_line = math.max(target_line, 3) -- Don't go above line 3 (first entry)
			vim.api.nvim_win_set_cursor(state.win, { target_line, 0 })
		else
			-- First time rendering, set to first entry
			vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
		end
	end
end

local function get_current_entry()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return nil
	end

	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local line = cursor[1]

	-- Line 1-2 are header
	if line <= 2 then
		return nil
	end

	local entry_idx = line - 2
	return state.entries[entry_idx]
end

-- Actions
local function enter_directory()
	local entry = get_current_entry()
	if not entry then return end

	if entry.type == 'directory' then
		state.current_dir = entry.path
		state.selected_files = {}
		render_directory()
	elseif entry.type == 'file' then
		-- Open file
		M.close()
		vim.cmd('edit ' .. vim.fn.fnameescape(entry.path))
	end
end

local function go_up()
	if state.current_dir ~= '/' then
		state.current_dir = vim.fn.fnamemodify(state.current_dir, ':h')
		state.selected_files = {}
		render_directory()
	end
end

local function toggle_selection()
	local entry = get_current_entry()
	if not entry or entry.is_parent then
		return
	end

	local idx = nil
	for i, path in ipairs(state.selected_files) do
		if path == entry.path then
			idx = i
			break
		end
	end

	if idx then
		table.remove(state.selected_files, idx)
	else
		table.insert(state.selected_files, entry.path)
	end

	render_directory()

	-- Move cursor down
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local next_line = math.min(cursor[1] + 1, vim.api.nvim_buf_line_count(state.buf))
	vim.api.nvim_win_set_cursor(state.win, { next_line, 0 })
end

local function mark_cut()
	local entry = get_current_entry()
	if not entry or entry.is_parent then
		return
	end

	-- Check if already marked for cut
	local already_marked = false
	for i, marked in ipairs(state.marked_files) do
		if marked.path == entry.path and state.mark_operation == 'cut' then
			-- Unmark
			table.remove(state.marked_files, i)
			if #state.marked_files == 0 then
				state.mark_operation = nil
			end
			render_directory()
			print('Unmarked: ' .. entry.name)
			return
		end
	end

	local files_to_mark = {}
	if #state.selected_files > 0 then
		for _, path in ipairs(state.selected_files) do
			table.insert(files_to_mark, { path = path })
		end
		state.selected_files = {}
	else
		table.insert(files_to_mark, { path = entry.path })
	end

	state.marked_files = files_to_mark
	state.mark_operation = 'cut'

	render_directory()
	print('Marked ' .. #files_to_mark .. ' file(s) for moving')
end

local function mark_copy()
	local entry = get_current_entry()
	if not entry or entry.is_parent then
		return
	end

	-- Check if already marked for copy
	local already_marked = false
	for i, marked in ipairs(state.marked_files) do
		if marked.path == entry.path and state.mark_operation == 'copy' then
			-- Unmark
			table.remove(state.marked_files, i)
			if #state.marked_files == 0 then
				state.mark_operation = nil
			end
			render_directory()
			print('Unmarked: ' .. entry.name)
			return
		end
	end

	local files_to_mark = {}
	if #state.selected_files > 0 then
		for _, path in ipairs(state.selected_files) do
			table.insert(files_to_mark, { path = path })
		end
		state.selected_files = {}
	else
		table.insert(files_to_mark, { path = entry.path })
	end

	state.marked_files = files_to_mark
	state.mark_operation = 'copy'

	render_directory()
	print('Marked ' .. #files_to_mark .. ' file(s) for copying')
end

local function paste()
	if #state.marked_files == 0 then
		print('No files marked')
		return
	end

	local dest_dir = state.current_dir
	local operation = state.mark_operation
	local count = 0

	for _, marked in ipairs(state.marked_files) do
		local source = marked.path
		local filename = vim.fn.fnamemodify(source, ':t')
		local dest = dest_dir .. '/' .. filename

		if source == dest then
			print('Skipping: source and destination are the same')
		else
			if operation == 'copy' then
				local success = vim.loop.fs_copyfile(source, dest)
				if success == 0 then
					count = count + 1
				else
					print('Failed to copy: ' .. source)
				end
			elseif operation == 'cut' then
				local success = vim.loop.fs_rename(source, dest)
				if success == 0 then
					count = count + 1
					-- Update buffer paths for moved files
					update_buffer_paths(source, dest)
				else
					print('Failed to move: ' .. source)
				end
			end
		end
	end

	if operation == 'cut' then
		state.marked_files = {}
		state.mark_operation = nil
	end

	render_directory()
	print(operation == 'cut' and 'Moved ' or 'Copied ' .. count .. ' file(s)')
end

local function create_file_or_dir()
	vim.ui.input({ prompt = 'Create (end with / for directory): ' }, function(input)
		if not input or input == '' then
			return
		end

		local path = state.current_dir .. '/' .. input

		if vim.endswith(input, '/') then
			-- Create directory
			local success = vim.loop.fs_mkdir(path, 493) -- 0755 in octal
			if success then
				print('Created directory: ' .. path)
			else
				print('Failed to create directory: ' .. path)
			end
		else
			-- Create file
			local fd = vim.loop.fs_open(path, 'w', 420) -- 0644 in octal
			if fd then
				vim.loop.fs_close(fd)
				print('Created file: ' .. path)
			else
				print('Failed to create file: ' .. path)
			end
		end

		render_directory()
	end)
end

local function delete_files()
	local entry = get_current_entry()
	if not entry or entry.is_parent then
		return
	end

	local files_to_delete = {}
	if #state.selected_files > 0 then
		files_to_delete = vim.deepcopy(state.selected_files)
	else
		table.insert(files_to_delete, entry.path)
	end

	local file_list = table.concat(vim.tbl_map(function(p)
		return '  ' .. vim.fn.fnamemodify(p, ':t')
	end, files_to_delete), '\n')

	local prompt = string.format('Delete %d file(s)?\n%s\n[Y/n]: ', #files_to_delete, file_list)

	vim.ui.input({ prompt = prompt, default = 'Y' }, function(input)
		if not input or (input ~= 'Y' and input ~= 'y' and input ~= '') then
			print('Cancelled')
			return
		end

		local function delete_recursive(path)
			local stat = vim.loop.fs_stat(path)
			if not stat then
				return false
			end

			if stat.type == 'directory' then
				local handle = vim.loop.fs_scandir(path)
				if handle then
					while true do
						local name, _ = vim.loop.fs_scandir_next(handle)
						if not name then break end
						delete_recursive(path .. '/' .. name)
					end
				end
				return vim.loop.fs_rmdir(path) == 0
			else
				return vim.loop.fs_unlink(path) == 0
			end
		end

		local function close_buffers_for_path(path)
			local buffers = vim.api.nvim_list_bufs()
			for _, buf in ipairs(buffers) do
				if vim.api.nvim_buf_is_loaded(buf) then
					local buf_name = vim.api.nvim_buf_get_name(buf)
					-- Close buffer if it's the deleted file or inside deleted directory
					if buf_name == path or vim.startswith(buf_name, path .. '/') then
						pcall(vim.api.nvim_buf_delete, buf, { force = true })
					end
				end
			end
		end

		local count = 0
		for _, path in ipairs(files_to_delete) do
			if delete_recursive(path) then
				count = count + 1
				close_buffers_for_path(path)
			else
				print('Failed to delete: ' .. path)
			end
		end

		state.selected_files = {}
		render_directory()
		print('Deleted ' .. count .. ' file(s)')
	end)
end

local function rename_file()
	local entry = get_current_entry()
	if not entry or entry.is_parent then
		return
	end

	vim.ui.input({ prompt = 'Rename to: ', default = entry.name }, function(input)
		if not input or input == '' or input == entry.name then
			return
		end

		local new_path = vim.fn.fnamemodify(entry.path, ':h') .. '/' .. input
		local success = vim.loop.fs_rename(entry.path, new_path)

		if success == 0 then
			print('Renamed to: ' .. input)
			-- Update buffer paths for renamed files/folders
			update_buffer_paths(entry.path, new_path)
			render_directory()
		else
			print('Failed to rename')
		end
	end)
end

-- Keymaps
local function setup_keymaps()
	local opts = { buffer = state.buf, noremap = true, silent = true }

	-- Navigation
	vim.keymap.set('n', 'j', function()
		local cursor = vim.api.nvim_win_get_cursor(state.win)
		local max_line = vim.api.nvim_buf_line_count(state.buf)
		if cursor[1] < max_line then
			vim.api.nvim_win_set_cursor(state.win, { cursor[1] + 1, 0 })
		end
	end, opts)

	vim.keymap.set('n', 'k', function()
		local cursor = vim.api.nvim_win_get_cursor(state.win)
		if cursor[1] > 3 then
			vim.api.nvim_win_set_cursor(state.win, { cursor[1] - 1, 0 })
		end
	end, opts)

	vim.keymap.set('n', '<Down>', function()
		local cursor = vim.api.nvim_win_get_cursor(state.win)
		local max_line = vim.api.nvim_buf_line_count(state.buf)
		if cursor[1] < max_line then
			vim.api.nvim_win_set_cursor(state.win, { cursor[1] + 1, 0 })
		end
	end, opts)

	vim.keymap.set('n', '<Up>', function()
		local cursor = vim.api.nvim_win_get_cursor(state.win)
		if cursor[1] > 3 then
			vim.api.nvim_win_set_cursor(state.win, { cursor[1] - 1, 0 })
		end
	end, opts)

	-- Enter directory or open file
	vim.keymap.set('n', '<CR>', enter_directory, opts)
	vim.keymap.set('n', 'l', enter_directory, opts)

	-- Go back (parent directory)
	vim.keymap.set('n', '<BS>', go_up, opts)
	vim.keymap.set('n', 'h', go_up, opts)

	-- Selection and operations
	vim.keymap.set('n', '<Tab>', toggle_selection, opts)
	vim.keymap.set('n', 'x', mark_cut, opts)
	vim.keymap.set('n', 'y', mark_copy, opts)
	vim.keymap.set('n', 'p', paste, opts)

	-- File operations
	vim.keymap.set('n', 'a', create_file_or_dir, opts)
	vim.keymap.set('n', 'd', delete_files, opts)
	vim.keymap.set('n', 'r', rename_file, opts)

	-- Close
	vim.keymap.set('n', '<Esc>', function() M.close() end, opts)
	vim.keymap.set('n', 'q', function() M.close() end, opts)
end

-- Main functions
function M.open()
	-- Save current buffer and window
	local current_buf = vim.api.nvim_get_current_buf()
	local current_win = vim.api.nvim_get_current_win()

	-- Only save previous state if we're not already in Dired
	if current_buf ~= state.buf then
		state.previous_buf = current_buf
		state.previous_win = current_win
		-- Save cursorline state from the previous window
		state.previous_cursorline = vim.api.nvim_win_get_option(current_win, 'cursorline')
		state.previous_wrap = vim.api.nvim_win_get_option(current_win, 'wrap')
		state.previous_number = vim.api.nvim_win_get_option(current_win, 'number')
		state.previous_relativenumber = vim.api.nvim_win_get_option(current_win, 'relativenumber')
		state.previous_cursorlineopt = vim.api.nvim_win_get_option(current_win, 'cursorlineopt')
	end

	-- Create buffer if it doesn't exist
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.buf, '[Dired]')
		vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
		vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'hide')
		vim.api.nvim_buf_set_option(state.buf, 'swapfile', false)
		vim.api.nvim_buf_set_option(state.buf, 'filetype', 'dired')
	end

	-- Open window
	vim.cmd('buffer ' .. state.buf)
	state.win = vim.api.nvim_get_current_win()

	-- Set window options
	vim.api.nvim_win_set_option(state.win, 'cursorline', true)
	vim.api.nvim_win_set_option(state.win, 'wrap', false)
	vim.api.nvim_win_set_option(state.win, 'number', false)
	vim.api.nvim_win_set_option(state.win, 'relativenumber', false)

	-- Setup highlight groups (ls -l --color style)
	vim.api.nvim_set_hl(0, 'DiredDirectory', { fg = '#7aa2f7', bold = true })
	vim.api.nvim_set_hl(0, 'DiredExecutable', { fg = '#73daca', bold = true })
	vim.api.nvim_set_hl(0, 'DiredSelected', { fg = '#e0af68', bold = true })
	vim.api.nvim_set_hl(0, 'DiredMarked', { fg = '#f7768e', bold = true })
	vim.api.nvim_set_hl(0, 'DiredPath', { fg = '#7dcfff', italic = true })
	vim.api.nvim_set_hl(0, 'DiredCursorLine', { bg = '#323750' })

	-- Override cursorline to use full line visual highlight
	vim.api.nvim_win_set_option(state.win, 'cursorlineopt', 'both')
	vim.api.nvim_win_set_hl_ns(state.win, state.ns_id)


	vim.api.nvim_win_set_hl_ns(state.win, state.ns_id)

	-- Setup keymaps
	setup_keymaps()

	-- Render
	state.current_dir = vim.fn.getcwd()
	render_directory()
end

function M.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		-- Get current window
		local current_win = vim.api.nvim_get_current_win()

		-- Only close if we're actually in the Dired window
		if current_win == state.win then
			if state.previous_buf and vim.api.nvim_buf_is_valid(state.previous_buf) then
				vim.api.nvim_win_set_buf(state.win, state.previous_buf)

				-- Restore cursorline state to what it was before opening Dired
				if state.previous_cursorline ~= nil then
					vim.api.nvim_win_set_option(state.win, 'cursorline', state.previous_cursorline)
					vim.api.nvim_win_set_option(state.win, 'wrap', state.previous_wrap)
					vim.api.nvim_win_set_option(state.win, 'number', state.previous_number)
					vim.api.nvim_win_set_option(state.win, 'relativenumber', state.previous_relativenumber)
					vim.api.nvim_win_set_option(state.win, 'cursorlineopt', state.previous_cursorlineopt)
				end
			else
				vim.cmd('enew')
			end
		end
	end

	-- Don't set state.win to nil, just keep it for next time
end

function M.toggle()
	-- Check if Dired buffer is currently visible in any window
	local dired_visible = false
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == state.buf then
				dired_visible = true
				state.win = win
				break
			end
		end
	end

	if dired_visible then
		M.close()
	else
		M.open()
	end
end

function M.setup(opts)
	opts = opts or {}

	-- Create command
	vim.api.nvim_create_user_command('Dired', function()
		M.toggle()
	end, {})

	-- Set up default keymap
	vim.keymap.set('n', '<leader>e', function()
		M.toggle()
	end, { noremap = true, silent = true, desc = 'Toggle Dired' })
end

return M
