local M = {}

local json = vim.json
local stdout = ""
local stderr = ""
local job_pid = nil
local stdin = nil
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
	if job_pid and stdin then
		vim.loop.write(stdin, header .. json_str)
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
		end

		if result.status or result.error then
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

	-- Create global stdin for message sending
	stdin = vim.loop.new_pipe(false)
	local stdout_pipe = vim.loop.new_pipe(false)
	local stderr_pipe = vim.loop.new_pipe(false)

	job_pid = vim.loop.spawn(cmd, {
		args = args,
		stdio = { stdin, stdout_pipe, stderr_pipe },
	}, function(code, signal)
		print("Process exited with code: " .. code)
		job_pid = nil
		stdin = nil
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
		elseif attempts > 200 then -- 5 seconds timeout
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

-- Run tests
function M.run_tests(callback)
	if not initialized or not job_pid then
		error("Service not initialized")
	end

	callback_id = callback_id + 1

	-- Special handling for test streaming
	callback_table[callback_id] = function(result)
		if callback then
			callback(result)

			-- Only remove the callback when we receive the final message
			if result.status then
				callback_table[callback_id] = nil
			end
		end
	end

	send_message({
		command = "test",
	})
end

-- Shutdown the service
function M.shutdown()
	if job_pid then
		-- Send shutdown command
		send_message({
			command = "shutdown",
		})

		-- Create a timer to wait for graceful shutdown
		local shutdown_timer = vim.loop.new_timer()
		local wait_count = 0
		local max_wait_attempts = 100 -- 10 second total wait time

		shutdown_timer:start(100, 100, function()
			wait_count = wait_count + 1

			if not job_pid then
				-- Process has already terminated
				shutdown_timer:stop()
				shutdown_timer:close()
			elseif wait_count >= max_wait_attempts then
				-- Force kill after waiting
				if job_pid then
					vim.loop.kill(job_pid, 9)
					job_pid = nil
					stdin = nil
				end
				shutdown_timer:stop()
				shutdown_timer:close()
			end
		end)

		return true
	end
	return false
end

-- Check if service is running
function M.is_running()
	return job_pid ~= nil and initialized
end

M.system_prompt = [[You are an expert programming assistant.


The context will include the *latest version* of the files throughout the session. The system prompt may change.
The person you are speaking to incredibly skilled. He knows what he is doing. Therefore, **do not add any comments to the code unless instructed to**

When you want to create files; you **must** show the new file in the following special format.

# The special code editing format
- Uses **file blocks**
- Starts with ```, and then the filename
- Ends with ```

## Example

```/lib/hello_world.py
def greeting():
    print("hello world!")
```

---

When you want to edit files; you **must** show the change in the following special format.

# The special code editing format
- Uses **file blocks**
- Starts with ```, and then the filename
- Ends with ```
- Uses **search and replace** blocks
    - Uses "<<<<<<< SEARCH" to find the original **lines** to replace
    - Continues to "=======",
    - Immediately follows to with replacement code
    - Finally, ends with  ">>>>>>> REPLACE"
- For each file edited, there can be  multiple search and replace commands
- The lines must match **exactly**. This means all indentation should be preserved, and should follow the style of that given file
- You *may* operate on different files by using multiple file blocks


## Example

Imagine we are working on the following file. Its most recent version will be presented in context as follows:

```/lib/hello_world.py
def greeting():
    print("hello world!")
```

And then, I ask you to make the hello world capitalized

I would expect you to give me the following:

```/lib/hello_world.py
<<<<<<< SEARCH
    print("hello world!")
=======
    print("Hello World!")
>>>>>>> REPLACE
```

After this, the file in context would **change to the most recent version**

```/lib/hello_world.py
def greeting():
    print("Hello World!")
```

After this, if I ask for a way to pass an arg that replaces "world":

You should give me:

```/lib/hello_world.py
<<<<<<< SEARCH
def greeting():
    print("Hello World!")
=======
def greeting(name):
    print(f"Hello {name}!")
>>>>>>> REPLACE
```
## An example with lines that are the same

Imagine we have this javascript file:

```/utils/helper.js
function setup() {
    console.log("Initializing...");
}

function teardown() {
    console.log("Initializing...");
}

setup();
teardown();
```
I would expect you to give me the following:

```/utils/helper.js
<<<<<<< SEARCH
function teardown() {
    console.log("Initializing...");
}
=======
function teardown() {
    console.log("Cleaning up...");
}
>>>>>>> REPLACE
```

## How you remove content

Here is how you would remove teardown

```/utils/helper.js
<<<<<<< SEARCH
function teardown() {
    console.log("Initializing...");
}

=======
>>>>>>> REPLACE
<<<<<<< SEARCH
teardown();
=======
>>>>>>> REPLACE
```

## Adding a new function in between teardown & setup on helper.js

```/utils/helper.js
<<<<<<< SEARCH
function teardown() {
=======
function intermediateStep() {
    console.log("Doing something in between...");
}

function teardown() {
>>>>>>> REPLACE
```

## Replacing a whole function

```/lib/math_utils.js
function findMax(numbers) {
  if (!numbers || numbers.length === 0) {
    return undefined;
  }
  let max = numbers[0];
  for (let i = 1; i < numbers.length; i++) {
    if (numbers[i] > max) {
      max = numbers[i];
    }
  }
  return max;
}

const data = [10, 5, 25, 3, 18];
const maximum = findMax(data);
console.log("Maximum value:", maximum);
```

Replacing the \`findMax\` function with \`Math.max\`

```/lib/math_utils.js
<<<<<<< SEARCH
function findMax(numbers) {
  if (!numbers || numbers.length === 0) {
    return undefined;
  }
  let max = numbers[0];
  for (let i = 1; i < numbers.length; i++) {
    if (numbers[i] > max) {
      max = numbers[i];
    }
  }
  return max;
}
=======
function findMax(numbers) {
  if (!numbers || numbers.length === 0) {
    return undefined;
  }
  return Math.max(...numbers);
}
>>>>>>> REPLACE
```

Notice how in all of the examples, no comments were added. Do not do this unless instructed to.


# General instructions
- The person you are speaking to is a highly skilled engineer, and they know what they are doing. Do **not** explain things without any **explicit** question. You may share your intent, but nothing beyond that, unless asked to.
- Anything is possible.
- Follow the code style of the file that you are operating in .
- If you are instructed to replace an entire file, **do not** use the search and replace blocks, but you may add the file path after the first three backticks.
]]

return M
