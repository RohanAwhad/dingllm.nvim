<img src="https://github.com/yacineMTB/dingllm.nvim/assets/10282244/d03ef83d-a5ee-4ddb-928f-742172f3c80c" alt="wordart (6)" style="width:200px;height:100px;">

### dingllm.nvim
Yacine's no frills LLM nvim scripts. free yourself, brothers and sisters

This is a really light config. I *will* be pushing breaking changes. I recommend reading the code and copying it over - it's really simple.

https://github.com/yacineMTB/dingllm.nvim/assets/10282244/07cf5ace-7e01-46e3-bd2f-5bec3bb019cc


### Credits
This extension woudln't exist if it weren't for https://github.com/melbaldove/llm.nvim

I diff'd on a fork of it until it was basically a rewrite. Thanks @melbaldove!

The main difference is that this uses events from plenary, rather than a timed async loop. I noticed that on some versions of nvim, melbaldove's extension would deadlock my editor. I suspected nio, so i just rewrote the extension. 

### lazy config
Add your API keys to your env (export it in zshrc or bashrc) 

```
	{
		"RohanAwhad/dingllm.nvim",
		dependencies = { "nvim-lua/plenary.nvim", "kkharji/sqlite.lua" },
		config = function()
			local generation_system_prompt =
				"You are a helpful expert AI Programmer. I have sent you the code uptill now and your job is to continue the generation. Do not talk at all. Only output valid code. Never ever output backticks like this ```. If there is a comment in 2-3 lines above, you should satisfy those comments. Other comments should be left alone. Do not output backticks. For coding, use 2 spaces for indentation, comment minimally."
			local system_prompt =
				"You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks. Type annotate the variables and function calls appropriately in python. For javascript or JSX do not add type annotations. For coding, use 2 spaces for indentation, comment minimally."
			local helpful_prompt =
				"You are a helpful assistant. What I have sent are my notes so far. You are very curt, yet helpful. For coding, use 2 spaces for indentation. Answer my queries."
			local dingllm = require("dingllm")

			local function ollama_generate()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "http://localhost:11434/v1/chat/completions",
					model = "qwen2.5-coder:0.5b",
					api_key_name = "ollama",
					system_prompt = generation_system_prompt,
					replace = false,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end
			local function ollama_generate_with_context()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "http://localhost:11434/v1/chat/completions",
					model = "qwen2.5-coder:0.5b",
					api_key_name = "ollama",
					system_prompt = generation_system_prompt,
					replace = false,
					build_context = true,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end


			local function ollama_replace()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "http://localhost:11434/v1/chat/completions",
					model = "qwen2.5-coder:14b",
					api_key_name = "ollama",
					system_prompt = system_prompt,
					replace = true,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end

			local function ollama_help()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "http://localhost:11434/v1/chat/completions",
					model = "qwen2.5-coder:14b",
					api_key_name = "ollama",
					system_prompt = helpful_prompt,
					replace = false,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end

			local function deepseek_generate()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.deepseek.com/chat/completions",
					model = "deepseek-chat",
					api_key_name = "DEEPSEEK_API_KEY",
					system_prompt = generation_system_prompt,
					replace = false,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end

			local function deepseek_replace()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.deepseek.com/chat/completions",
					model = "deepseek-chat",
					api_key_name = "DEEPSEEK_API_KEY",
					system_prompt = system_prompt,
					replace = true,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end

			local function deepseek_help()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.deepseek.com/chat/completions",
					model = "deepseek-reasoner",
					api_key_name = "DEEPSEEK_API_KEY",
					system_prompt = helpful_prompt,
					replace = false,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_deepseek_reasoner_spec_data)
			end

			local function openai_generate()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.openai.com/v1/chat/completions",
					model = "gpt-4o-2024-08-06",
					api_key_name = "OPENAI_API_KEY",
					system_prompt = generation_system_prompt,
					replace = false,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end
			local function openai_replace()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.openai.com/v1/chat/completions",
					model = "gpt-4o-2024-08-06",
					api_key_name = "OPENAI_API_KEY",
					system_prompt = system_prompt,
					replace = true,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end

			local function openai_help()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.openai.com/v1/chat/completions",
					model = "gpt-4o-2024-08-06",
					api_key_name = "OPENAI_API_KEY",
					system_prompt = helpful_prompt,
					replace = false,
				}, dingllm.make_openai_spec_curl_args, dingllm.handle_openai_spec_data)
			end

			local function anthropic_generate()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.anthropic.com/v1/messages",
					model = "claude-3-5-sonnet-20241022",
					api_key_name = "ANTHROPIC_API_KEY",
					system_prompt = generation_system_prompt,
					replace = false,
				}, dingllm.make_anthropic_spec_curl_args, dingllm.handle_anthropic_spec_data)
			end

			local function anthropic_help()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.anthropic.com/v1/messages",
					model = "claude-3-5-sonnet-20241022",
					api_key_name = "ANTHROPIC_API_KEY",
					system_prompt = helpful_prompt,
					replace = false,
				}, dingllm.make_anthropic_spec_curl_args, dingllm.handle_anthropic_spec_data)
			end

			local function anthropic_replace()
				dingllm.invoke_llm_and_stream_into_editor({
					url = "https://api.anthropic.com/v1/messages",
					model = "claude-3-5-sonnet-20241022",
					api_key_name = "ANTHROPIC_API_KEY",
					system_prompt = system_prompt,
					replace = true,
				}, dingllm.make_anthropic_spec_curl_args, dingllm.handle_anthropic_spec_data)
			end

			vim.keymap.set({ "n", "v" }, "<leader>t", deepseek_generate, { desc = "llm deepseek generate" })
			vim.keymap.set({ "n", "v" }, "<leader>tr", deepseek_replace, { desc = "llm deepseek replace" })
			vim.keymap.set({ "n", "v" }, "<leader>th", deepseek_help, { desc = "llm deepseek help" })

			vim.keymap.set({ "n", "v" }, "<leader>k", ollama_generate, { desc = "llm ollama generate" })
			vim.keymap.set({ "n", "v" }, "<leader>kc", ollama_generate_with_context, { desc = "llm ollama generate with context" })
			vim.keymap.set({ "n", "v" }, "<leader>kr", ollama_replace, { desc = "llm ollama replace" })
			vim.keymap.set({ "n", "v" }, "<leader>kh", ollama_help, { desc = "llm ollama_help" })

			vim.keymap.set({ "n", "v" }, "<leader>l", openai_generate, { desc = "llm openai generate" })
			vim.keymap.set({ "n", "v" }, "<leader>lr", openai_replace, { desc = "llm openai replace" })
			vim.keymap.set({ "n", "v" }, "<leader>lh", openai_help, { desc = "llm openai_help" })

			vim.keymap.set({ "n", "v" }, "<leader>i", anthropic_generate, { desc = "llm anthropic generate" })
			vim.keymap.set({ "n", "v" }, "<leader>ir", anthropic_replace, { desc = "llm anthropic replace" })
			vim.keymap.set({ "n", "v" }, "<leader>ih", anthropic_help, { desc = "llm anthropic_help" })
		end,
	},
```

### Documentation

read the code dummy
