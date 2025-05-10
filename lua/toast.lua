local M = {}

local active_toast = {
	win = nil,
	buf = nil,
	timer = nil,
}

-- Create toast window
local function create_window()
	local width = 40
	local height = 3
	local row = vim.api.nvim_get_option("lines") - height - 4
	local col = vim.api.nvim_get_option("columns") - width - 1

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, false, {

		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		focusable = false,
		noautocmd = true,
	})

	-- Set window options
	vim.api.nvim_win_set_option(win, "winhl", "Normal:FloatBorder")

	-- Initialize with empty lines
	vim.api.nvim_buf_set_lines(buf, 0, 3, false, { "", "", "" })

	return buf, win
end

-- Cancel any existing toast
local function cancel_toast()
	if active_toast.timer then
		active_toast.timer:stop()
		active_toast.timer:close()
		active_toast.timer = nil
	end

	if active_toast.win and vim.api.nvim_win_is_valid(active_toast.win) then
		vim.api.nvim_win_close(active_toast.win, true)
	end

	if active_toast.buf and vim.api.nvim_buf_is_valid(active_toast.buf) then
		vim.api.nvim_buf_delete(active_toast.buf, { force = true })
	end

	active_toast.win = nil
	active_toast.buf = nil
end

-- Show toast with model info and streamed text
function M.show_model_toast(model, text)
	-- Schedule to avoid UI conflicts
	vim.schedule(function()
		-- Cancel any existing toast
		cancel_toast()

		-- Create new toast
		local buf, win = create_window()
		active_toast.buf = buf
		active_toast.win = win

		-- Set content
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "Model: " .. model })

		-- Set highlights
		vim.api.nvim_buf_add_highlight(buf, -1, "Statement", 0, 0, 6) -- "Model:" in statement color
		vim.api.nvim_buf_add_highlight(buf, -1, "Character", 0, 7, -1) -- model name in identifier color

		-- Update text if provided
		if text and text ~= "" then
			local max_len = 38 -- Max display width
			if #text > max_len then
				text = text:sub(1, max_len - 3) .. "..."
			end
			vim.api.nvim_buf_set_lines(buf, 1, 2, false, { text })
		end
	end)
end

-- Update the existing toast with new text
function M.update_toast(text)
	vim.schedule(function()
		-- Only update if there's an active toast
		if
			active_toast.win
			and vim.api.nvim_win_is_valid(active_toast.win)
			and active_toast.buf
			and vim.api.nvim_buf_is_valid(active_toast.buf)
		then
			if text and text ~= "" then
				-- Split text into lines and truncate each line
				local lines = {}
				for line in text:gmatch("[^\n]+") do
					if #line > 38 then
						line = line:sub(1, 35) .. "..."
					end
					table.insert(lines, line)
					if #lines >= 2 then
						break
					end -- Only show last 2 lines
				end
				vim.api.nvim_buf_set_lines(active_toast.buf, 1, 3, false, lines)
				vim.api.nvim_buf_add_highlight(active_toast.buf, -1, "LspReferenceRead", 1, 0, -1) -- "Model:" in statement color
			end
		end
	end)
end

-- Close the toast
function M.close_toast()
	vim.schedule(function()
		cancel_toast()
	end)
end

-- Setup function to initialize the plugin
function M.setup()
	-- Define highlight groups if needed
	vim.cmd([[
        highlight default link ToastTitle Statement
        highlight default link ToastModel Identifier
        highlight default link ToastText Comment
    ]])
end

return M
