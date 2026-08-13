do
    local ask_questions = require("codecompanion.interactions.chat.tools.builtin.ask_questions")
    local run = ask_questions.cmds[1]
    ask_questions.cmds[1] = function(self, args, input)
        for i, question in ipairs(args.questions or {}) do
            if type(question) == "string" then
                args.questions[i] = { header = "Q" .. i, question = question }
            elseif type(question) == "table" then
                if type(question.question) ~= "string" then
                    question.question = tostring(question.question or question.text or "")
                end
                if type(question.header) ~= "string" then
                    question.header = "Q" .. i
                end
                for j, option in ipairs(question.options or {}) do
                    if type(option) == "string" then
                        question.options[j] = { label = option }
                    elseif type(option) == "table" and type(option.label) ~= "string" then
                        option.label = tostring(option.label or option.text or ("Option " .. j))
                    end
                end
            end
        end
        return run(self, args, input)
    end
end

local chat_state_path = vim.fs.joinpath(vim.fn.stdpath("state"), "codecompanion-last-chat.json")
local chat_state = { adapter = "ollama", models = {} }

do
    local ok, content = pcall(vim.fn.readfile, chat_state_path)
    if ok and content[1] then
        local decoded_ok, decoded = pcall(vim.json.decode, table.concat(content, "\n"))
        if decoded_ok and type(decoded) == "table" then
            chat_state = vim.tbl_deep_extend("force", chat_state, decoded)
        end
    end
end

local function save_chat_state()
    vim.fn.mkdir(vim.fs.dirname(chat_state_path), "p")
    local ok, result = pcall(vim.fn.writefile, { vim.json.encode(chat_state) }, chat_state_path)
    if not ok or result == -1 then
        vim.notify("Could not save CodeCompanion chat defaults: " .. tostring(result), vim.log.levels.WARN)
    end
end

local function default_chat_adapter()
    local model = chat_state.models[chat_state.adapter]
    if model then
        return { name = chat_state.adapter, model = model }
    end
    return chat_state.adapter
end

local function ollama_default_model(adapter)
    local choices = adapter.schema.model.choices
    if type(choices) == "function" then
        choices = choices(adapter, { async = false })
    end

    if type(choices) ~= "table" then
        return chat_state.models.ollama or ""
    end

    local installed = vim.iter(choices):map(function(key, value)
        if type(key) == "number" then
            return type(value) == "table" and value.id or value
        end
        return type(value) == "table" and value.id or key
    end):filter(function(model)
        return type(model) == "string" and model ~= ""
    end):totable()
    table.sort(installed)

    if chat_state.models.ollama and vim.list_contains(installed, chat_state.models.ollama) then
        return chat_state.models.ollama
    end

    chat_state.models.ollama = installed[1]
    save_chat_state()
    return chat_state.models.ollama or ""
end

require("codecompanion").setup({
    adapters = {
        http = {
            ollama = function()
                return require("codecompanion.adapters").extend("ollama", {
                    schema = {
                        model = { default = ollama_default_model },
                        keep_alive = { default = "30m" },
                        num_ctx = { default = 16384 },
                    },
                })
            end,
        },
    },
    interactions = {
        chat = {
            adapter = default_chat_adapter(),
            keymaps = {
                change_model = {
                    modes = { n = "gm" },
                    callback = function(chat)
                        return require("codecompanion.interactions.chat.keymaps.change_adapter").select_model(chat)
                    end,
                    description = "Change model (current adapter)",
                },
            },
            tools = {
                opts = {
                    -- Load @agent's tools (run/edit/read files, search, etc.) into
                    -- every chat by default instead of typing `@agent` each time.
                    default_tools = { "agent" },
                },
            },
        },
        inline = {
            adapter = "ollama",
        },
        cli = {
            agent = "claude_code",
            agents = {
                claude_code = {
                    cmd = "claude",
                    args = {},
                    description = "Claude Code CLI",
                    provider = "terminal",
                },
            },
        },
    },
    display = {
        chat = {
            window = {
                position = "right",
                width = 0.25,
            },
        },
    },
    extensions = {
        history = {
            enabled = true,
        },
    },
})

local Chat = require("codecompanion.interactions.chat")

local function selected_model(chat)
    if chat.adapter.type == "acp" then
        if chat.acp_connection then
            local models = chat.acp_connection:get_models()
            if models and models.currentModelId then
                return models.currentModelId
            end
        end
        return chat.adapter.defaults and chat.adapter.defaults.model
    end

    if chat.adapter.type == "http" then
        local model = chat.settings and chat.settings.model or chat.adapter.schema.model.default
        return type(model) == "string" and model or nil
    end

    return chat.adapter.defaults and chat.adapter.defaults.model
end

vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatDone",
    desc = "Remember the adapter and model from the last successful chat",
    callback = function(args)
        local chat = Chat.buf_get_chat((args.data or {}).bufnr)
        if not chat or chat.status ~= "success" or not chat.adapter or type(chat.adapter.name) ~= "string" then
            return
        end

        local model = selected_model(chat)
        chat_state.adapter = chat.adapter.name
        if type(model) == "string" and model ~= "" then
            chat_state.models[chat_state.adapter] = model
        end
        require("codecompanion.config").interactions.chat.adapter = default_chat_adapter()
        save_chat_state()
    end,
})

local function host_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "codecompanion" then
            return win
        end
    end
end

local function find_chat(adapter_name, model)
    for _, entry in ipairs(Chat.buf_get_chat()) do
        local chat = entry.chat
        if chat.adapter and chat.adapter.name == adapter_name and (not model or selected_model(chat) == model) then
            return chat
        end
    end
end

local function adapter_available(adapter_name)
    if adapter_name == "ollama" then
        local result = vim.system({
            "curl",
            "--silent",
            "--fail",
            "--max-time",
            "1",
            "http://localhost:11434/api/tags",
        }):wait()
        if result.code ~= 0 then
            vim.notify("Ollama is not running on localhost:11434", vim.log.levels.WARN)
            return false
        end
    end
    return true
end

local function open_chat(force_new)
    local adapter_name = chat_state.adapter
    local model = chat_state.models[adapter_name]
    if not adapter_available(adapter_name) then
        return
    end

    local host = host_win()
    local chat = not force_new and find_chat(adapter_name, model)

    if chat then
        if host then
            vim.api.nvim_win_set_buf(host, chat.bufnr)
            chat.ui.winnr = host
            vim.api.nvim_set_current_win(host)
        else
            chat.ui:open()
            vim.api.nvim_set_current_win(chat.ui.winnr)
        end
        return
    end

    -- No chat for the last successful adapter/model pair yet.
    local command = "CodeCompanionChat adapter=" .. vim.fn.fnameescape(adapter_name)
    if model then
        command = command .. " model=" .. vim.fn.fnameescape(model)
    end
    vim.cmd(command)
    if not (host and vim.api.nvim_win_is_valid(host)) then return end

    local new_win = vim.api.nvim_get_current_win()
    if new_win == host then return end

    local new_buf = vim.api.nvim_win_get_buf(new_win)
    vim.api.nvim_win_close(new_win, false)
    vim.api.nvim_win_set_buf(host, new_buf)
    local created = Chat.buf_get_chat(new_buf)
    if created then created.ui.winnr = host end
    vim.api.nvim_set_current_win(host)
end
vim.api.nvim_create_user_command("ChatDelete", function()
    require("ricardo.chat_delete").open()
end, { desc = "Select saved CodeCompanion chats to delete" })

vim.api.nvim_create_user_command("ChatClearAll", function()
    vim.ui.select({ "Yes", "No" }, { prompt = "Delete ALL saved CodeCompanion chats?" }, function(choice)
        if choice ~= "Yes" then
            return
        end
        local history = require("codecompanion").extensions.history
        local save_ids = vim.tbl_keys(history.get_chats())
        local count = require("ricardo.chat_delete").delete(save_ids)
        vim.notify("Deleted " .. count .. " saved chat(s)", vim.log.levels.INFO)
    end)
end, { desc = "Delete all saved CodeCompanion chats" })

local function open_last_chat() open_chat(false) end
local function new_last_chat() open_chat(true) end

vim.keymap.set({ "n", "v" }, "<leader>co", open_last_chat,
    { noremap = true, desc = "CodeCompanion chat (last successful provider/model)" })
vim.keymap.set({ "n", "v" }, "<leader>cc", open_last_chat,
    { noremap = true, desc = "CodeCompanion chat (last successful provider/model)" })
vim.api.nvim_set_keymap('n', '<leader>ch',
    '<cmd>CodeCompanionHistory<CR>',
    { noremap = true, silent = true, desc = "CodeCompanion chat history" })

vim.keymap.set({ "n", "v" }, "<leader>cno", new_last_chat,
    { noremap = true, desc = "CodeCompanion new chat (last successful provider/model)" })
vim.keymap.set({ "n", "v" }, "<leader>cnc", new_last_chat,
    { noremap = true, desc = "CodeCompanion new chat (last successful provider/model)" })
