<img src="https://github.com/yacineMTB/dingllm.nvim/assets/10282244/d03ef83d-a5ee-4ddb-928f-742172f3c80c" alt="wordart (6)" style="width:200px;height:100px;">

### dingllm.nvim
This is a really light config. I *will* be pushing breaking changes. I recommend reading the code and copying it over - it's really simple.

https://github.com/yacineMTB/dingllm.nvim/assets/10282244/07cf5ace-7e01-46e3-bd2f-5bec3bb019cc


### Credits
Credits to: https://github.com/yacineMTB/dingllm.nvim 

I fork'd and separated the backend and wrote it in python to provide support for tool execution and loops.

Thanks @yacineMTB

## How to run:

Install `buzzllm` backend:
```bash
python3.12 -m pip install --upgrade "git+https://github.com/rohanawhad/buzzllm.git" --break-system-packages
```

### lazy config
Add your API keys to your env (export it in zshrc or bashrc) 

```
	{
		"RohanAwhad/dingllm.nvim",
		dependencies = { "nvim-lua/plenary.nvim", "kkharji/sqlite.lua" },
    config = function()
      local dingllm = require("dingllm")

      local function search_web_and_answer()
        dingllm.invoke_buzzllm({
          url = "https://api.openai.com/v1/chat/completions",
          model = "gpt-5.1",
          api_key_name = "OPENAI_API_KEY",
          system_prompt = "websearch",
          provider = "openai-chat",
          replace = false,
          think = false,
        })
      end

      local function search_codebase_and_answer()
        dingllm.invoke_buzzllm({
          url = "https://api.openai.com/v1/chat/completions",
          model = "gpt-5.1",
          api_key_name = "OPENAI_API_KEY",
          system_prompt = "codesearch",
          provider = "openai-chat",
          replace = false,
          think = false,
        })
      end

      local function openai_help()
        dingllm.invoke_buzzllm({
          url = "https://api.openai.com/v1/chat/completions",
          model = "gpt-5.1",
          api_key_name = "OPENAI_API_KEY",
          system_prompt = "helpful",
          provider = "openai-chat",
          replace = false,
          think = true,
        })
      end

      local function openai_replace()
        dingllm.invoke_buzzllm({
          url = "https://api.openai.com/v1/chat/completions",
          model = "gpt-5.1",
          api_key_name = "OPENAI_API_KEY",
          system_prompt = "replace",
          provider = "openai-chat",
          replace = false,
          think = false,
        })
      end

      local function openai_hack()
        dingllm.invoke_buzzllm({
          url = "https://api.openai.com/v1/chat/completions",
          model = "gpt-5.1",
          api_key_name = "OPENAI_API_KEY",
          system_prompt = "hackhub",
          provider = "openai-chat",
          replace = false,
          think = true,
        })
      end

      -- using claude from VERTEX
      local project_id = os.getenv("ANTHROPIC_VERTEX_PROJECT_ID")
      local location = os.getenv("CLOUD_ML_REGION")
      local anthropic_model = os.getenv("ANTHROPIC_MODEL")
      local anthropic_vertex_url = "https://"
        .. location
        .. "-aiplatform.googleapis.com/v1/projects/"
        .. project_id
        .. "/locations/"
        .. location
        .. "/publishers/anthropic/models/"
        .. anthropic_model
        .. ":streamRawPredict"

      local function anthropic_help()
        dingllm.invoke_buzzllm({
          url = anthropic_vertex_url,
          model = anthropic_model,
          api_key_name = "ANTHROPIC_API_KEY",
          system_prompt = "helpful",
          provider = "vertexai-anthropic",
          replace = false,
          think = true,
        })
      end

      local function anthropic_replace()
        dingllm.invoke_buzzllm({
          url = anthropic_vertex_url,
          model = anthropic_model,
          api_key_name = "ANTHROPIC_API_KEY",
          system_prompt = "replace",
          provider = "vertexai-anthropic",
          replace = true,
          think = false,
        })
      end

      local function anthropic_hack()
        dingllm.invoke_buzzllm({
          url = anthropic_vertex_url,
          model = anthropic_model,
          api_key_name = "ANTHROPIC_API_KEY",
          system_prompt = "hackhub",
          provider = "vertexai-anthropic",
          replace = false,
          think = true,
        })
      end

      function append_current_file_to_list()
        local current_file = vim.fn.expand("%")
        if current_file == "" then
          return
        end
        local files_txt = ".dingllm/files.txt"
        vim.fn.mkdir(".dingllm", "p")
        local lines = vim.fn.filereadable(files_txt) == 1 and vim.fn.readfile(files_txt) or {}
        -- Check if current_file is already in the list
        local already_exists = false
        for _, line in ipairs(lines) do
          if line == current_file then
            already_exists = true
            break
          end
        end
        if not already_exists then
          table.insert(lines, current_file)
          vim.fn.writefile(lines, files_txt)
        end
        local files_txt_abs = vim.fn.fnamemodify(files_txt, ":p")
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
          if buf_name == files_txt_abs then
            -- Window is already open, reload it from disk
            local buf = vim.api.nvim_win_get_buf(win)
            vim.api.nvim_buf_call(buf, function()
              vim.cmd("edit!")
            end)
            return
          end
        end
        local current_win = vim.api.nvim_get_current_win()
        local height = math.floor(vim.o.lines * 0.3)
        vim.cmd("botright " .. height .. "split " .. files_txt)
        vim.api.nvim_set_current_win(current_win)
      end

      -- SEARCH and REPLACE block generator and applier
      vim.keymap.set({ "n", "v" }, "<leader>ai", anthropic_hack, { desc = "anthropic generate changes" })
      vim.keymap.set({ "n", "v" }, "<leader>ap", openai_hack, { desc = "openai generate changes" })
      vim.keymap.set({ "v" }, "<leader>ac", dingllm.apply_hackhub_changes, { desc = "apply changes" })

      -- utils to append current file to context
      vim.keymap.set({ "n" }, "<leader>gp", append_current_file_to_list, { desc = "yank filepath" })
      vim.keymap.set({ "n" }, "<leader>gP", ':let @+=expand("%:p")<CR>', { desc = "yank abs filepath" })

      -- llm funcs
      vim.keymap.set({ "n", "v" }, "<leader>h", openai_help, { desc = "llm openaihelp" })
      vim.keymap.set({ "n", "v" }, "<leader>hr", openai_replace, { desc = "llm openai replace" })

      vim.keymap.set({ "n", "v" }, "<leader>i", anthropic_help, { desc = "llm anthropic help" })
      vim.keymap.set({ "n", "v" }, "<leader>ir", anthropic_replace, { desc = "llm anthropic replace" })

      -- specific llm calls
      vim.keymap.set({ "n", "v" }, "<leader>we", search_web_and_answer, { desc = "llm websearch" })
      vim.keymap.set({ "n", "v" }, "<leader>cs", search_codebase_and_answer, { desc = "llm codesearch" })
    end,
	},
```

### Documentation

read the code dummy
