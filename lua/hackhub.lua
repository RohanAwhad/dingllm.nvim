local M = {}

local json = vim.json
local stdout = ""
local stderr = ""
local job_pid = nil
local initialized = false
local callback_table = {}
local callback_id = 0

-- Parse messages with Content-Length header
local function parse_message(data)
	local content_length = data:match("Content%-Length: (%d+)")
	if not content_length then
		return nil
	end

	local payload_start = data:find("\r\n\r\n") or data:find("\n\n")
	if not payload_start then
		return nil
	end

	payload_start = payload_start + (data:find("\r\n\r\n") and 4 or 2)
	local payload = data:sub(payload_start, payload_start + tonumber(content_length) - 1)

	local success, result = pcall(json.decode, payload)
	if not success then
		return nil
	end

	return result
end

-- Send a message following the protocol
local function send_message(message)
	local json_str = json.encode(message)
	local header = "Content-Length: " .. #json_str .. "\n\n"
	if job_pid then
		vim.loop.write(job_pid, header .. json_str)
	else
		error("Process not started")
	end
end

-- Process incoming messages
local function process_data(err, data)
	if err then
		print("Error: " .. err)
		return
	end

	if not data then
		return
	end

	stdout = stdout .. data
	local result = parse_message(stdout)

	if result then
		-- Clear consumed data
		stdout = stdout:sub(#stdout - #json.encode(result))

		-- Handle initialization response
		if result.status == "initialized" then
			initialized = true
			print("Initialized. Files indexed: " .. result.files_indexed)
			return
		end

		-- Handle callbacks
		if callback_id > 0 and callback_table[callback_id] then
			callback_table[callback_id](result)
			callback_table[callback_id] = nil
		end
	end
end

-- Start the hackhub service
function M.start(project_path)
	if job_pid then
		M.shutdown()
	end

	stdout = ""
	stderr = ""
	initialized = false

	local cmd = "/Users/rohan/1_Porn/russ_cox_code_search/master/.venv/bin/python"
	local args = {
		"/Users/rohan/1_Porn/russ_cox_code_search/master/main.py",
		project_path,
	}

	local stdin = vim.loop.new_pipe(false)
	local stdout_pipe = vim.loop.new_pipe(false)
	local stderr_pipe = vim.loop.new_pipe(false)

	job_pid = vim.loop.spawn(cmd, {
		args = args,
		stdio = { stdin, stdout_pipe, stderr_pipe },
	}, function(code, signal)
		print("Process exited with code: " .. code)
		job_pid = nil
	end)

	vim.loop.read_start(stdout_pipe, process_data)
	vim.loop.read_start(stderr_pipe, function(err, data)
		if data then
			stderr = stderr .. data
		end
	end)

	-- Wait for initialization
	local attempts = 0
	local wait_for_init = vim.loop.new_timer()
	wait_for_init:start(100, 100, function()
		attempts = attempts + 1
		if initialized then
			wait_for_init:stop()
			wait_for_init:close()
		elseif attempts > 50 then -- 5 seconds timeout
			wait_for_init:stop()
			wait_for_init:close()
			error("Failed to initialize hackhub service")
		end
	end)

	return job_pid ~= nil
end

-- Search for a pattern
function M.search(pattern, max_results, callback)
	if not initialized or not job_pid then
		error("Service not initialized")
	end

	callback_id = callback_id + 1
	callback_table[callback_id] = callback

	send_message({
		command = "search",
		pattern = pattern,
		max_results = max_results or 100,
	})
end

-- Apply changes
function M.apply_changes(changes, callback)
	if not initialized or not job_pid then
		error("Service not initialized")
	end

	callback_id = callback_id + 1
	callback_table[callback_id] = callback

	send_message({
		command = "apply_changes",
		changes = changes,
	})
end

-- Shutdown the service
function M.shutdown()
	if job_pid then
		send_message({
			command = "shutdown",
		})

		-- Give it a moment to shut down gracefully
		vim.defer_fn(function()
			if job_pid then
				vim.loop.kill(job_pid, 9) -- Force kill if still running
				job_pid = nil
			end
		end, 500)

		return true
	end
	return false
end

-- Check if service is running
function M.is_running()
	return job_pid ~= nil and initialized
end

return M

-- Usage example:
--
-- ```lua
-- local hackhub = require("hackhub")
--
-- -- Start the service
-- hackhub.start("/path/to/your/project")
--
-- -- Search for a pattern
-- hackhub.search("myFunction", 10, function(result)
--   if result.status == "success" then
--     print("Found " .. result.total_matches .. " matches")
--     for _, match in ipairs(result.matches) do
--       print(match.file)
--     end
--   else
--     print("Error: " .. (result.error or "Unknown error"))
--   end
-- end)
--
-- -- Apply changes
-- local changes = "```path/to/file.py\n<<<<<<< SEARCH\nold code\n=======\nnew code\n>>>>>>> REPLACE\n```"
-- hackhub.apply_changes(changes, function(result)
--   if result.status == "success" then
--     print("Changes applied successfully")
--   else
--     print("Error applying changes: " .. (result.error or "Unknown error"))
--   end
-- end)
--
-- -- Shutdown when done
-- hackhub.shutdown()
-- ```
