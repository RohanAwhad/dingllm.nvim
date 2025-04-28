local M = {}
local Job = require("plenary.job")
local sqlite = require("sqlite")
local ding_path = vim.fn.expand("~/.dingllm")

if vim.fn.isdirectory(ding_path) == 0 then
	vim.fn.mkdir(ding_path, "p")
end

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
			table.insert(file_paths, line)
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
			table.insert(
				result,
				string.format(
					"<file>\n<filepath>%s</filepath>\n<file_content>%s</file_content>\n</file>",
					path,
					content
				)
			)
			content_file:close()
		else
			table.insert(
				result,
				string.format(
					"<file>\n<filepath>%s</filepath>\n<file_content>Error: Could not read file %s</file_content>\n</file>",
					path,
					path
				)
			)
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

function M.make_anthropic_spec_curl_args(opts, prompt, system_prompt)
	local url = opts.url
	local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
	local data = {
		system = system_prompt,
		messages = { { role = "user", content = prompt } },
		model = opts.model,
		stream = true,
		max_tokens = 4096,
	}
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
	local data = {
		messages = { { role = "system", content = system_prompt }, { role = "user", content = prompt } },
		model = opts.model,
		temperature = 0.7,
		stream = true,
		max_tokens = opts.max_tokens or 4096,
	}
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

local function write_string_at_cursor(str, cursor_window, cursor_position)
	vim.schedule(function()
		local buffer = vim.api.nvim_win_get_buf(cursor_window)
		local row, col = cursor_position[1] - 1, cursor_position[2]

		-- Create namespace if it doesn't exist
		local ns_id = vim.api.nvim_create_namespace("dingllm_insertion")

		-- We need to get current position if this isn't the first call
		local mark_id = vim.b[buffer].dingllm_mark_id

		if not mark_id then
			-- First insertion - create the mark
			mark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, row, col, {})
			vim.b[buffer].dingllm_mark_id = mark_id
		end

		-- Get current mark position (which tracks edits)
		local pos = vim.api.nvim_buf_get_extmark_by_id(buffer, ns_id, mark_id, {})
		local mark_row, mark_col = pos[1], pos[2]

		-- Get current line at mark position
		local line = vim.api.nvim_buf_get_lines(buffer, mark_row, mark_row + 1, false)[1] or ""

		local lines = vim.split(str, "\n")
		pcall(vim.cmd, "undojoin")

		if #lines == 1 then
			-- Single line insertion
			local new_line = line:sub(1, mark_col) .. lines[1] .. line:sub(mark_col + 1)
			vim.api.nvim_buf_set_lines(buffer, mark_row, mark_row + 1, false, { new_line })

			-- Update mark position
			vim.api.nvim_buf_set_extmark(buffer, ns_id, mark_row, mark_col + #lines[1], { id = mark_id })
		else
			-- Multi-line insertion
			local first_line = line:sub(1, mark_col) .. lines[1]
			local last_line = lines[#lines] .. line:sub(mark_col + 1)

			local new_lines = { first_line }
			for i = 2, #lines - 1 do
				table.insert(new_lines, lines[i])
			end
			table.insert(new_lines, last_line)

			vim.api.nvim_buf_set_lines(buffer, mark_row, mark_row + 1, false, new_lines)

			-- Update mark position to end of inserted text
			vim.api.nvim_buf_set_extmark(buffer, ns_id, mark_row + #lines - 1, #lines[#lines], { id = mark_id })
		end
	end)
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

function M.handle_anthropic_spec_data(data_stream, cursor_window, cursor_position, event_state)
	if event_state == "content_block_delta" then
		local json = vim.json.decode(data_stream)
		if json.delta and json.delta.text then
			local content = json.delta.text
			write_string_at_cursor(content, cursor_window, cursor_position)
			return content
		end
	end
end

function M.handle_openai_spec_data(data_stream, cursor_window, cursor_position)
	if data_stream:match('"delta":') then
		local json = vim.json.decode(data_stream)
		if json.choices and json.choices[1] and json.choices[1].delta then
			local content = json.choices[1].delta.content
			if content then
				write_string_at_cursor(content, cursor_window, cursor_position)
				return content
			end
		end
	end
end

function M.handle_research_spec_data(data_stream, cursor_window, cursor_position)
	if data_stream:match('"delta":') then
		local json = vim.json.decode(data_stream)
		if json.choices and json.choices[1] and json.choices[1].delta then
			local content = json.choices[1].delta.content
			if content then
				write_string_at_cursor(content, cursor_window, cursor_position)
				return content
			end
		end
	end
end

function M.handle_deepseek_reasoner_spec_data(data_stream, cursor_window, cursor_position)
	if data_stream:match('"delta":') then
		local json = vim.json.decode(data_stream)
		if json.choices and json.choices[1] and json.choices[1].delta then
			local content = json.choices[1].delta.content
			local reasoning = json.choices[1].delta.reasoning_content
			if content and type(content) == "string" then
				write_string_at_cursor(content, cursor_window, cursor_position)
				return content
			elseif reasoning and type(reasoning) == "string" then
				write_string_at_cursor(reasoning, cursor_window, cursor_position)
				return reasoning
			end
		end
	end
end

local group = vim.api.nvim_create_augroup("DING_LLM_AutoGroup", { clear = true })
local active_job = nil

function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
	local full_output = ""

	vim.api.nvim_clear_autocmds({ group = group })
	local prompt = get_prompt(opts)
	local system_prompt
	if not opts.research then
		system_prompt = opts.system_prompt
			or "You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly"
	end
	local args = make_curl_args_fn(opts, prompt, system_prompt)
	local curr_event_state = nil

	local cursor_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(cursor_window)

	local function parse_and_call(line)
		local event = line:match("^event: (.+)$")
		if event then
			curr_event_state = event
			return
		end
		local data_match = line:match("^data: (.+)$")
		if data_match then
			local content = handle_data_fn(data_match, cursor_window, cursor_position, curr_event_state)
			if content then
				return content
			end
		end
	end

	if active_job then
		active_job:shutdown()
		active_job = nil
	end

	active_job = Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			local content = parse_and_call(out)
			-- Append to full output when content received
			if content then
				full_output = full_output .. (content or "")
			end
		end,
		on_stderr = function(_, _) end,
		on_exit = function()
			active_job = nil
			vim.schedule(function()
				local buffer = vim.api.nvim_get_current_buf()
				local mark_id = vim.b[buffer].dingllm_mark_id
				if mark_id then
					vim.api.nvim_buf_del_extmark(buffer, vim.api.nvim_create_namespace("dingllm_insertion"), mark_id)
					vim.b[buffer].dingllm_mark_id = nil
				end
				-- Save prompt and output to DB
				save_to_db(opts.system_prompt, prompt, full_output, opts.model)
			end)
		end,
	})

	active_job:start()

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "DING_LLM_ESCAPE",
		callback = function()
			if active_job then
				active_job:shutdown()
				print("LLM streaming cancelled")
				active_job = nil
			end
		end,
	})

	vim.api.nvim_set_keymap("n", "<Esc>", ":doautocmd User DING_LLM_ESCAPE<CR>", { noremap = true, silent = true })
	return active_job
end

return M
