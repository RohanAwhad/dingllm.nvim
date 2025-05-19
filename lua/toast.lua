local M = {}

-- Table to store all active toasts, indexed by job_id
local active_toasts = {}

-- Constants for toast dimensions and styling
local TOAST_WIDTH = 45
local TOAST_BASE_HEIGHT = 2
local TOAST_PADDING = 2

-- Create toast window for a specific job
local function create_window(job_id, total_jobs)
	local width = TOAST_WIDTH
	local height = TOAST_BASE_HEIGHT

	-- Calculate position based on job_id and total active jobs
	-- This will stack toasts from bottom to top with some padding
	local base_row = vim.api.nvim_get_option("lines") - height - 4
	local row = base_row - ((job_id - 1) % 5) * (height + TOAST_PADDING)
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

-- Cancel a specific toast by job_id
local function cancel_toast(job_id)
	local toast = active_toasts[job_id]
	if not toast then
		return
	end

	if toast.timer then
		toast.timer:stop()
		toast.timer:close()
	end

	if toast.win and vim.api.nvim_win_is_valid(toast.win) then
		vim.api.nvim_win_close(toast.win, true)
	end

	if toast.buf and vim.api.nvim_buf_is_valid(toast.buf) then
		vim.api.nvim_buf_delete(toast.buf, { force = true })
	end

	active_toasts[job_id] = nil

	-- Reposition remaining toasts
	M.reposition_toasts()
end

-- Cancel all active toasts
local function cancel_all_toasts()
	for job_id, _ in pairs(active_toasts) do
		cancel_toast(job_id)
	end
end

-- Reposition toasts after one is added or removed
function M.reposition_toasts()
	local job_ids = {}
	for id, _ in pairs(active_toasts) do
		table.insert(job_ids, id)
	end

	table.sort(job_ids)

	for i, job_id in ipairs(job_ids) do
		local toast = active_toasts[job_id]
		if toast.win and vim.api.nvim_win_is_valid(toast.win) then
			local base_row = vim.api.nvim_get_option("lines") - TOAST_BASE_HEIGHT - 4
			local row = base_row - ((i - 1) % 5) * (TOAST_BASE_HEIGHT + TOAST_PADDING)

			vim.api.nvim_win_set_config(toast.win, {
				relative = "editor",
				row = row,
				col = vim.api.nvim_get_option("columns") - TOAST_WIDTH - 1,
			})
		end
	end
end

-- Show toast with job ID, model info and status
function M.show_model_toast(job_id, model, status)
	-- Schedule to avoid UI conflicts
	vim.schedule(function()
		-- Check if we already have a toast for this job
		if active_toasts[job_id] then
			M.update_job_status(job_id, status)
			return
		end

		-- Create new toast
		local buf, win = create_window(job_id, vim.tbl_count(active_toasts) + 1)

		active_toasts[job_id] = {
			buf = buf,
			win = win,
			timer = nil,
			model = model,
			status = status,
		}

		-- Set content
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "Job " .. job_id .. " | Model: " .. model })
		-- vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "Status: " .. status })

		-- Set highlights
		vim.api.nvim_buf_add_highlight(buf, -1, "Statement", 0, 0, 4 + #tostring(job_id))
		vim.api.nvim_buf_add_highlight(buf, -1, "Character", 0, 7 + #tostring(job_id), -1)
		vim.api.nvim_buf_add_highlight(buf, -1, "Type", 1, 0, 7)
		vim.api.nvim_buf_add_highlight(buf, -1, "Special", 1, 8, -1)

		-- Reposition all toasts
		M.reposition_toasts()
	end)
end

-- Update the content for a specific job toast
function M.update_toast(job_id, text)
	vim.schedule(function()
		local toast = active_toasts[job_id]
		-- Only update if the toast exists and is valid
		if
			toast
			and toast.win
			and vim.api.nvim_win_is_valid(toast.win)
			and toast.buf
			and vim.api.nvim_buf_is_valid(toast.buf)
		then
			if text and text ~= "" then
				-- Split text into lines and truncate each line
				local lines = {}
				for line in text:gmatch("[^\n]+") do
					if #line > 38 then
						line = line:sub(1, 35) .. "..."
					end
					table.insert(lines, line)
					if #lines >= 1 then
						break
					end -- Only show last line
				end

				-- Only update the last line
				vim.api.nvim_buf_set_lines(toast.buf, 1, 2, false, lines)
				vim.api.nvim_buf_add_highlight(toast.buf, -1, "LspReferenceRead", 2, 0, -1)
			end
		end
	end)
end

-- Update status for a specific job
function M.update_job_status(job_id, status)
	vim.schedule(function()
		local toast = active_toasts[job_id]
		if
			toast
			and toast.win
			and vim.api.nvim_win_is_valid(toast.win)
			and toast.buf
			and vim.api.nvim_buf_is_valid(toast.buf)
		then
			toast.status = status
			vim.api.nvim_buf_set_lines(toast.buf, 1, 2, false, { "Status: " .. status })
			vim.api.nvim_buf_add_highlight(toast.buf, -1, "Type", 1, 0, 7)
			vim.api.nvim_buf_add_highlight(toast.buf, -1, "Special", 1, 8, -1)
		end
	end)
end

-- Close a specific toast by job_id
function M.close_job_toast(job_id)
	vim.schedule(function()
		cancel_toast(job_id)
	end)
end

-- Close all toasts
function M.close_toast()
	vim.schedule(function()
		cancel_all_toasts()
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
