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

require("codecompanion").setup({
    adapters = {
        http = {
            ollama = function()
                return require("codecompanion.adapters").extend("ollama", {
                    schema = {
                        model = { default = "gpt-oss:20b" },
                        keep_alive = { default = "30m" },
                        num_ctx = { default = 16384 },
                    },
                })
            end,
        },
    },
    interactions = {
        chat = {
            adapter = "ollama",
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

local function host_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "codecompanion" then
            return win
        end
    end
end

local function find_chat(adapter_name)
    for _, entry in ipairs(Chat.buf_get_chat()) do
        if entry.chat.adapter and entry.chat.adapter.name == adapter_name then
            return entry.chat
        end
    end
end

local function open_chat(adapter_name)
    local host = host_win()
    local chat = find_chat(adapter_name)

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

    -- no chat for this adapter yet
    vim.cmd("CodeCompanionChat adapter=" .. adapter_name)
    if not (host and vim.api.nvim_win_is_valid(host)) then return end

    local new_win = vim.api.nvim_get_current_win()
    if new_win == host then return end

    local new_buf = vim.api.nvim_win_get_buf(new_win)
    vim.api.nvim_win_close(new_win, false)
    vim.api.nvim_win_set_buf(host, new_buf)
    local created = find_chat(adapter_name)
    if created then created.ui.winnr = host end
    vim.api.nvim_set_current_win(host)
end
vim.api.nvim_create_user_command("ChatDelete", function()
    local chat = require("codecompanion.interactions.chat").buf_get_chat(vim.api.nvim_get_current_buf())
    if not chat or not chat.opts.save_id then
        vim.notify("No active CodeCompanion chat to delete", vim.log.levels.WARN)
        return
    end
    require("codecompanion").extensions.history.delete_chat(chat.opts.save_id)
    chat:close()
    vim.notify("Deleted chat from history", vim.log.levels.INFO)
end, { desc = "Delete the current CodeCompanion chat from history" })

vim.api.nvim_create_user_command("ChatClearAll", function()
    vim.ui.select({ "Yes", "No" }, { prompt = "Delete ALL saved CodeCompanion chats?" }, function(choice)
        if choice ~= "Yes" then
            return
        end
        local history = require("codecompanion").extensions.history
        local count = 0
        for save_id, _ in pairs(history.get_chats()) do
            history.delete_chat(save_id)
            count = count + 1
        end
        vim.notify("Deleted " .. count .. " saved chat(s)", vim.log.levels.INFO)
    end)
end, { desc = "Delete all saved CodeCompanion chats" })

vim.keymap.set({ "n", "v" }, "<leader>co", function() open_chat("ollama") end,
    { noremap = true, desc = "CodeCompanion chat (Ollama)" })
vim.keymap.set({ "n", "v" }, "<leader>cc", function() open_chat("claude_code") end,
    { noremap = true, desc = "CodeCompanion chat (Claude Code ACP)" })
vim.api.nvim_set_keymap('n', '<leader>ch',
    '<cmd>CodeCompanionHistory<CR>',
    { noremap = true, silent = true, desc = "CodeCompanion chat history" })

-- Always spawns a fresh chat buffer, unlike <leader>co/<leader>cc which
-- refocus an existing chat on that adapter -- use these to start a second
-- conversation while one is already streaming a response.
vim.keymap.set({ "n", "v" }, "<leader>cno", function() vim.cmd("CodeCompanionChat adapter=ollama") end,
    { noremap = true, desc = "CodeCompanion new chat (Ollama)" })
vim.keymap.set({ "n", "v" }, "<leader>cnc", function() vim.cmd("CodeCompanionChat adapter=claude_code") end,
    { noremap = true, desc = "CodeCompanion new chat (Claude Code ACP)" })
