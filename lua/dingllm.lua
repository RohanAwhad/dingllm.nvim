local M = {}
local Job = require("plenary.job")
local sqlite = require("sqlite")
local hackhub = require("hackhub")
local toast = require("toast")
local ding_path = vim.fn.expand("~/.dingllm")

if vim.fn.isdirectory(ding_path) == 0 then
	vim.fn.mkdir(ding_path, "p")
end

-- Initialize toast module
toast.setup()

-- Start hackhub with the current project directory
local function init_hackhub()
	local project_dir = vim.fn.getcwd()
	if project_dir and project_dir ~= "" then
		hackhub.start(project_dir)
	end
end

-- Initialize hackhub when dingllm is loaded
init_hackhub()
M.hackhub_prompt = hackhub.system_prompt

-- Set up autocmd to shut down hackhub when Neovim exits
vim.api.nvim_create_autocmd({ "VimLeavePre", "VimLeave" }, {
	callback = function()
		if hackhub.is_running() then
			hackhub.shutdown()
		end
	end,
	group = vim.api.nvim_create_augroup("HackHubCleanup", { clear = true }),
})

local function save_to_db(instruction, prompt, output, model)
	local db_path = vim.fn.expand("~/.dingllm/calls.db")
	local db = sqlite.new(db_path)
	db:open()
	db:eval(
		[[CREATE TABLE IF NOT EXISTS calls (id INTEGER PRIMARY KEY, instruction TEXT, input TEXT, output TEXT, model TEXT, created_at INTEGER);]]
	)
	local ok, err = pcall(function()
		db:insert("calls", {
			instruction = instruction,
			input = prompt,
			output = output,
			model = model,
			created_at = os.time(),
		})
	end)
	db:close()
end

local function get_api_key(name)
	return os.getenv(name)
end

function M.expand_glob_pattern(pattern)
	-- Use vim's built-in glob() function instead of shell commands
	local expanded_files = vim.fn.glob(pattern, false, true)

	local files = {}
	for _, file in ipairs(expanded_files) do
		if vim.fn.filereadable(file) == 1 then
			table.insert(files, file)
		end
	end

	return files
end

function M.build_context()
	-- Define the path to files.txt
	local files_txt_path = vim.fn.getcwd() .. "/.dingllm/files.txt"

	-- Read the contents of files.txt
	local file = io.open(files_txt_path, "r")
	if not file then
		return ""
	end

	-- Read all lines from files.txt
	local file_paths = {}
	for line in file:lines() do
		-- Trim whitespace and ignore empty lines
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" then
			-- Check if line contains glob pattern
			if line:match("[*]") then
				print("expanding glob pattern")
				local expanded_files = M.expand_glob_pattern(line)
				for _, expanded_file in ipairs(expanded_files) do
					table.insert(file_paths, expanded_file)
				end
			else
				table.insert(file_paths, line)
			end
		end
	end
	file:close()

	-- Concatenate contents of each file
	local result = {}
	for _, path in ipairs(file_paths) do
		-- Resolve relative paths based on current working directory
		local full_path = path
		if not path:match("^/") then
			full_path = vim.fn.getcwd() .. "/" .. path
		end

		local content_file = io.open(full_path, "r")
		if content_file then
			local content = content_file:read("*all")
			table.insert(result, string.format("```%s\n%s\n```\n", path, content))
			content_file:close()
		end
	end

	-- Return concatenated string
	return table.concat(result, "\n")
end

function M.get_lines_until_cursor()
	local current_buffer = vim.api.nvim_get_current_buf()
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)
	local row = cursor_position[1]

	local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

	return table.concat(lines, "\n")
end

function M.get_visual_selection()
	local _, srow, scol = unpack(vim.fn.getpos("v"))
	local _, erow, ecol = unpack(vim.fn.getpos("."))

	if vim.fn.mode() == "V" then
		if srow > erow then
			return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
		else
			return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
		end
	end

	if vim.fn.mode() == "v" then
		if srow < erow or (srow == erow and scol <= ecol) then
			return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
		else
			return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
		end
	end

	if vim.fn.mode() == "\22" then
		local lines = {}
		if srow > erow then
			srow, erow = erow, srow
		end
		if scol > ecol then
			scol, ecol = ecol, scol
		end
		for i = srow, erow do
			table.insert(
				lines,
				vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1]
			)
		end
		return lines
	end
end

function M.make_openai_responses_spec_curl_args(opts, prompt, system_prompt)
	local url = opts.url
	local data = {
		instructions = system_prompt,
		input = prompt,
		model = opts.model,
		tools = opts.tools or nil,
		stream = true,
		store = false,
		max_infer_iters = opts.max_infer_iters or 10,
	}

	if opts.think then
		data.max_tokens = 40000
		data.thinking = { type = "enabled", budget_tokens = 32000 } -- this is bad. doesn't follow system_prompt
	else
		data.max_tokens = 8192
	end

	local args = {
		"-N",
		"-X",
		"POST",
		"-H",
		"accept:application/json",
		"-H",
		"Content-Type: application/json",
		"-d",
		vim.json.encode(data),
	}
	table.insert(args, url)
	return args
end

function M.make_anthropic_spec_curl_args(opts, prompt, system_prompt)
	local url = opts.url
	local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
	local data = {
		system = system_prompt,
		messages = { { role = "user", content = prompt } },
		model = opts.model,
		stream = true,
	}

	if opts.think then
		data.max_tokens = 40000
		data.thinking = { type = "enabled", budget_tokens = 32000 } -- this is bad. doesn't follow system_prompt
	else
		data.max_tokens = 8192
	end

	local args = { "-N", "-X", "POST", "-H", "Content-Type: application/json", "-d", vim.json.encode(data) }
	if api_key then
		table.insert(args, "-H")
		table.insert(args, "x-api-key: " .. api_key)
		table.insert(args, "-H")
		table.insert(args, "anthropic-version: 2023-06-01")
	end
	table.insert(args, url)
	return args
end

function M.make_openai_spec_curl_args(opts, prompt, system_prompt)
	local url = opts.url
	local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
	local role = "system"
	if opts.model == "o3" then
		role = "developer"
	end
	local data = {
		messages = { { role = role, content = system_prompt }, { role = "user", content = prompt } },
		model = opts.model,
		stream = true,
	}

	if opts.model == "o3" then
		data.reasoning_effort = "high"
		data.response_format = { type = "text" }
		-- data.max_completion_tokens = opts.max_tokens or 4096
	else
		data.temperature = 0.7
		data.max_tokens = opts.max_tokens or 4096
	end

	-- print(vim.json.encode(data))

	local args = { "-N", "-X", "POST", "-H", "Content-Type: application/json", "-d", vim.json.encode(data) }
	if api_key then
		table.insert(args, "-H")
		table.insert(args, "Authorization: Bearer " .. api_key)
	end
	table.insert(args, url)
	return args
end

-- TODO: in future implement API key logic
function M.make_research_spec_curl_args(opts, prompt)
	local url = opts.url
	local test
	if opts.test then
		test = opts.test
	else
		test = false
	end
	local data = {
		query = prompt,
		model = opts.model,
		test = test,
	}
	local args = { "-N", "-X", "POST", "-H", "Content-Type: application/json", "-d", vim.json.encode(data) }
	table.insert(args, url)
	return args
end

local function get_prompt(opts)
	local replace = opts.replace
	local visual_lines = M.get_visual_selection()
	local prompt = ""

	-- Get text from prompt sources
	if visual_lines then
		prompt = table.concat(visual_lines, "\n")
		if replace then
			vim.api.nvim_command("normal! d")
			vim.api.nvim_command("normal! k")
		else
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", false, true, true), "nx", false)
		end
	else
		prompt = M.get_lines_until_cursor()
		local context = M.build_context()
		if context and context ~= "" then
			prompt = context .. "\n\n" .. prompt
		end
	end

	local function count_lines(s)
		local count = 0
		for _ in string.gmatch(s, "[^\r\n]+") do
			count = count + 1
		end
		return count
	end
	print("Number of Lines in Prompt:", count_lines(prompt))
	return prompt
end

function M.handle_anthropic_spec_data(data_stream, buffer, ns_id, mark_id, event_state, state)
	local json
	local content

	if event_state == "message_start" then
		json = vim.json.decode(data_stream)
		if json.message and json.message.id then
			content = "=== Assistant Response ID: " .. json.message.id .. " Start ===\n\n"
			M.write_string_at_cursor(content, buffer, ns_id, mark_id)
		end
	end
	if event_state == "content_block_delta" then
		json = vim.json.decode(data_stream)
		-- log reasoning output
		if json.delta and json.delta.thinking then
			content = json.delta.thinking
			-- M.write_string_at_cursor(content, buffer, ns_id, mark_id)
			-- state.added_separator = false -- Reset for next reasoning block
			return content
		end

		-- log actual output
		if json.delta and json.delta.text then
			-- if not (state.reasoning_complete or state.added_separator) then
			-- 	M.write_string_at_cursor("\n\n=== THINKING END ===\n\n", buffer, ns_id, mark_id)
			-- 	state.added_separator = true
			-- end
			content = json.delta.text
			M.write_string_at_cursor(content, buffer, ns_id, mark_id)
			state.reasoning_complete = true
			return content
		end
	end
	if event_state == "message_stop" then
		content = "\n\n=== Assistant Response End ===\n\n"
		M.write_string_at_cursor(content, buffer, ns_id, mark_id)
	end
end

function M.handle_openai_responses_spec_data(data_stream, buffer, ns_id, mark_id, event_state, state)
	local content
	local json = vim.json.decode(data_stream)
	if not state.message_start then
		content = "=== Assistant Response"
		if json.response and json.response.id then
			content = content .. " ID: " .. json.response.id
		end
		content = content .. " Start ===\n\n"
		M.write_string_at_cursor(content, buffer, ns_id, mark_id)
		state.message_start = true
	end

	if json.type and json.type == "response.output_text.delta" then
		local content = json.delta
		if content and type(content) == "string" and content ~= "" then
			M.write_string_at_cursor(content, buffer, ns_id, mark_id)
			state.reasoning_complete = true
			return content
		end
	end

	if json.type and json.type == "response.completed" then
		content = "\n\n=== Assistant Response End ===\n\n"
		M.write_string_at_cursor(content, buffer, ns_id, mark_id)
	end
end

function M.handle_openai_spec_data(data_stream, buffer, ns_id, mark_id, event_state, state)
	local content
	if data_stream:match('"delta":') then
		local json = vim.json.decode(data_stream)
		if not state.message_start then
			content = "=== Assistant Response"
			if json.id then
				content = content .. " ID: " .. json.id
			end
			content = content .. " Start ===\n\n"
			M.write_string_at_cursor(content, buffer, ns_id, mark_id)
			state.message_start = true
		end

		if json.choices and json.choices[1] and json.choices[1].delta then
			content = json.choices[1].delta.content
			local reasoning = json.choices[1].delta.reasoning

			if content and type(content) == "string" and content ~= "" then
				-- -- First content after reasoning - add 2 newlines
				-- if not (state.reasoning_complete or state.added_separator) then
				-- 	M.write_string_at_cursor("\n\n=== THINKING END ===\n\n", buffer, ns_id, mark_id)
				-- 	state.added_separator = true
				-- end
				M.write_string_at_cursor(content, buffer, ns_id, mark_id)
				state.reasoning_complete = true
				return content
			elseif reasoning and type(reasoning) == "string" then
				-- M.write_string_at_cursor(reasoning, buffer, ns_id, mark_id)
				-- state.added_separator = false -- Reset for next reasoning block
				return reasoning
			end
		end
	end

	if data_stream == "[DONE]" then
		content = "\n\n=== Assistant Response End ===\n\n"
		M.write_string_at_cursor(content, buffer, ns_id, mark_id)
	end
end

function M.handle_research_spec_data(data_stream, buffer, ns_id, mark_id)
	if data_stream:match('"delta":') then
		local json = vim.json.decode(data_stream)
		if json.choices and json.choices[1] and json.choices[1].delta then
			local content = json.choices[1].delta.content
			if content then
				M.write_string_at_cursor(content, buffer, ns_id, mark_id)
				return content
			end
		end
	end
end

function M.handle_deepseek_reasoner_spec_data(data_stream, buffer, ns_id, mark_id, event_state, state)
	local content
	if data_stream:match('"delta":') then
		local json = vim.json.decode(data_stream)
		if not state.message_start and json.id then
			content = "=== Assistant Response ID: " .. json.id .. " Start ===\n\n"
			M.write_string_at_cursor(content, buffer, ns_id, mark_id)
			state.message_start = true
		end

		if json.choices and json.choices[1] and json.choices[1].delta then
			content = json.choices[1].delta.content
			local reasoning = json.choices[1].delta.reasoning_content

			if content and type(content) == "string" then
				-- First content after reasoning - add 2 newlines
				-- if not (state.reasoning_complete or state.added_separator) then
				-- 	M.write_string_at_cursor("\n\n=== THINKING END ===\n\n", buffer, ns_id, mark_id)
				-- 	state.added_separator = true
				-- end
				M.write_string_at_cursor(content, buffer, ns_id, mark_id)
				state.reasoning_complete = true
				return content
			elseif reasoning and type(reasoning) == "string" then
				-- M.write_string_at_cursor(reasoning, buffer, ns_id, mark_id)
				state.added_separator = false -- Reset for next reasoning block
				return reasoning
			end
		end
	end

	if data_stream == "[DONE]" then
		content = "\n\n=== Assistant Response End ===\n\n"
		M.write_string_at_cursor(content, buffer, ns_id, mark_id)
	end
end

local group = vim.api.nvim_create_augroup("DING_LLM_AutoGroup", { clear = true })
local active_jobs = {}
local next_job_id = 1

function M.write_string_at_cursor(str, buffer, ns_id, mark_id)
	vim.schedule(function()
		local pos = vim.api.nvim_buf_get_extmark_by_id(buffer, ns_id, mark_id, {})
		local mark_row, mark_col = pos[1], pos[2]

		local line = vim.api.nvim_buf_get_lines(buffer, mark_row, mark_row + 1, false)[1] or ""
		local lines = vim.split(str, "\n")
		pcall(vim.cmd, "undojoin")

		if #lines == 1 then
			local new_line = line:sub(1, mark_col) .. lines[1] .. line:sub(mark_col + 1)
			vim.api.nvim_buf_set_lines(buffer, mark_row, mark_row + 1, false, { new_line })
			vim.api.nvim_buf_set_extmark(buffer, ns_id, mark_row, mark_col + #lines[1], { id = mark_id })
		else
			local first_line = line:sub(1, mark_col) .. lines[1]
			local last_line = lines[#lines] .. line:sub(mark_col + 1)
			local new_lines = { first_line }
			for i = 2, #lines - 1 do
				table.insert(new_lines, lines[i])
			end
			table.insert(new_lines, last_line)
			vim.api.nvim_buf_set_lines(buffer, mark_row, mark_row + 1, false, new_lines)
			vim.api.nvim_buf_set_extmark(buffer, ns_id, mark_row + #lines - 1, #lines[#lines], { id = mark_id })
		end
	end)
end

function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
	local job_id = next_job_id
	next_job_id = next_job_id + 1

	local full_output = ""
	local buffer = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local original_row = cursor_pos[1] - 1
	local original_col = cursor_pos[2]

	-- Create unique namespace and mark for this job
	local ns_id = vim.api.nvim_create_namespace("dingllm_job_" .. job_id)
	local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, original_row, original_col, {})

	local prompt = get_prompt(opts)
	local system_prompt = not opts.research and opts.system_prompt or nil

	local args = make_curl_args_fn(opts, prompt, system_prompt)
	local curr_event_state = nil
	local state = { added_separator = false, reasoning_complete = false, message_start = false }

	-- Show initial toast with model info
	toast.show_model_toast(job_id, opts.model or "Unknown model", "Starting...")

	local function parse_and_call(line)
		local event = line:match("^event: (.+)$")
		if event then
			curr_event_state = event
			return
		end
		local data_match = line:match("^data: (.+)$")
		if data_match then
			local content = handle_data_fn(data_match, buffer, ns_id, mark_id, curr_event_state, state)
			if content then
				-- Update toast with latest content
				toast.update_toast(job_id, content)
				return content
			end
		end
	end

	local job = Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			local content = parse_and_call(out)
			if content then
				full_output = full_output .. content
			end
		end,
		on_stderr = function(_, err)
			-- -- Log errors but continue processing
			-- if err and err ~= "" then
			-- 	vim.schedule(function()
			-- 		vim.api.nvim_echo({ { "Error in job " .. job_id .. ": " .. err, "ErrorMsg" } }, false, {})
			-- 	end)
			-- end
		end,
		-- In the on_exit handler:
		on_exit = function(_, code)
			vim.schedule(function()
				-- Cleanup
				vim.api.nvim_buf_del_extmark(buffer, ns_id, mark_id)
				active_jobs[job_id] = nil
				save_to_db(opts.system_prompt, prompt, full_output, opts.model)

				-- Close toast immediately if successful, otherwise show failed status
				if code == 0 then
					toast.close_job_toast(job_id)
				else
					toast.update_job_status(job_id, "Failed")
				end

				-- Close toast if no active jobs (only needed for failed cases)
				if vim.tbl_isempty(active_jobs) then
					toast.close_toast()
				end
			end)
		end,
	})

	active_jobs[job_id] = {
		job = job,
		ns_id = ns_id,
		mark_id = mark_id,
		buffer = buffer,
		model = opts.model,
	}

	job:start()

	-- Only set up escape handler if this is the first job
	if vim.tbl_count(active_jobs) == 1 then
		vim.api.nvim_clear_autocmds({ group = group })

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "DING_LLM_ESCAPE",
			callback = function()
				for id, job_data in pairs(active_jobs) do
					job_data.job:shutdown()
					vim.api.nvim_buf_del_extmark(job_data.buffer, job_data.ns_id, job_data.mark_id)
					print("LLM streaming cancelled for job " .. id)
				end
				active_jobs = {}
				toast.close_toast()
			end,
		})

		vim.api.nvim_set_keymap("n", "<Esc>", ":doautocmd User DING_LLM_ESCAPE<CR>", { noremap = true, silent = true })
	end

	return job_id
end

-- Run tests and stream output into the editor
function M.run_hackhub_tests()
	if not hackhub.is_running() then
		print("HackHub is not running. Starting...")
		init_hackhub()

		-- Give hackhub a moment to initialize
		vim.defer_fn(function()
			if hackhub.is_running() then
				M.run_tests()
			else
				print("Failed to start HackHub")
			end
		end, 1000)
	else
		M.run_tests()
	end
end

-- Helper function to actually run the tests and stream the output
function M.run_tests()
	local buffer = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local original_row = cursor_pos[1] - 1
	local original_col = cursor_pos[2]

	-- Create namespace and mark for this test run
	local ns_id = vim.api.nvim_create_namespace("dingllm_test_run")
	local mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, original_row, original_col, {})

	-- Write test run header
	M.write_string_at_cursor("\n=== Test Run Started ===\n\n", buffer, ns_id, mark_id)

	hackhub.run_tests(function(result)
		if result.type == "stdout" then
			M.write_string_at_cursor("[stdout] " .. result.output .. "\n", buffer, ns_id, mark_id)
		elseif result.type == "stderr" then
			M.write_string_at_cursor("[stderr] " .. result.output .. "\n", buffer, ns_id, mark_id)
		elseif result.status then
			local message = "\n=== Test Run Completed with code " .. (result.return_code or "unknown") .. " ===\n"
			M.write_string_at_cursor(message, buffer, ns_id, mark_id)
		elseif result.error then
			M.write_string_at_cursor("\n=== Test Run Failed: " .. result.error .. " ===\n", buffer, ns_id, mark_id)
		end
	end)
end

-- Apply changes to code selected in visual mode
function M.apply_hackhub_changes()
	local visual_text = M.get_visual_selection()
	if not visual_text or #visual_text == 0 then
		print("No text selected")
		return
	end

	local changes = table.concat(visual_text, "\n")

	if not hackhub.is_running() then
		print("HackHub is not running. Starting...")
		init_hackhub()

		-- Give hackhub a moment to initialize
		vim.defer_fn(function()
			if hackhub.is_running() then
				M.apply_changes(changes)
			else
				print("Failed to start HackHub")
			end
		end, 1000)
	else
		M.apply_changes(changes)
	end
end

-- Helper function to handle the actual change application
function M.apply_changes(changes)
	hackhub.apply_changes(changes, function(result)
		if result.status == "success" then
			print("Changes applied successfully")
		else
			print("Error applying changes: " .. (result.error or "Unknown error"))
		end
	end)
end

function M.get_docstrings()
	local docstrings_path = vim.fn.getcwd() .. "/.dingllm/docstrings.json"
	local docstrings_file = io.open(docstrings_path, "r")
	if not docstrings_file then
		print("docstrings.json not found in .dingllm directory")
		return
	end
	local docstrings = vim.json.decode(docstrings_file:read("*a"))
	docstrings_file:close()

	-- Build markdown table of files with docstrings
	local docstrings_table = {}
	for path, entry in pairs(docstrings) do
		table.insert(docstrings_table, string.format("| `%s` | %s |", path, entry.docstring))
	end
	return table.concat(docstrings_table, "\n")
end

return M
