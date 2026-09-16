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
-- `sessions` maps a loaded session file's path (`v:this_session`) to the
-- adapter/model last used while that session was active -- see
-- `resolve_last_chat` and the `VimLeavePre` autocmd below.
-- No default `adapter` -- nothing to assume before a chat has ever
-- succeeded. `default_chat_adapter`, `resolve_last_chat` and `open_chat_with`
-- all treat a nil adapter as "no memory yet" and fall back to codecompanion's
-- own built-in default instead.
local chat_state = { models = {}, sessions = {} }

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

-- Ollama's `choices()` (and thus `schema.get_default`) blocks for up to 3s
-- on its own network round trip whenever ollama isn't reachable -- and that
-- runs on *every* chat/inline resolution of the adapter, not just the ones
-- started through this file's keymaps. `ollama_reachable()` never blocks:
-- it returns the last known result instantly and, if that result is stale,
-- kicks off a fire-and-forget async probe that updates the cache for next
-- time. Nothing calls this on its own -- it only ever runs as a side effect
-- of actually trying to open/create a chat (provider_valid, below, and
-- ollama_default_model), never at startup or idle.
local OLLAMA_URL = "http://localhost:11434/api/tags"
local OLLAMA_CHECK_TTL = 30 -- seconds; re-probe occasionally so starting ollama later gets picked up
local ollama_reachable_cache = { checked_at = -math.huge, ok = false, checking = false }

local function refresh_ollama_reachable_async()
    if ollama_reachable_cache.checking then
        return
    end
    -- No point pinging localhost:11434 on a machine that doesn't even have
    -- ollama installed -- this is a synchronous PATH lookup, not a network
    -- call, so it's cheap enough to redo on every TTL refresh.
    if vim.fn.executable("ollama") == 0 then
        ollama_reachable_cache.checked_at = vim.uv.now() / 1000
        ollama_reachable_cache.ok = false
        return
    end
    ollama_reachable_cache.checking = true
    vim.system({
        "curl",
        "--silent",
        "--fail",
        "--max-time",
        "0.5",
        OLLAMA_URL,
    }, {}, function(result)
        ollama_reachable_cache.checking = false
        ollama_reachable_cache.checked_at = vim.uv.now() / 1000
        ollama_reachable_cache.ok = result.code == 0
    end)
end

local function ollama_reachable()
    local now = vim.uv.now() / 1000
    if now - ollama_reachable_cache.checked_at >= OLLAMA_CHECK_TTL then
        refresh_ollama_reachable_async()
    end
    return ollama_reachable_cache.ok
end

local function ollama_default_model(adapter)
    if not ollama_reachable() then
        return chat_state.models.ollama or ""
    end

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

-- Provider availability, for the <leader>cn picker and for deciding whether
-- a remembered adapter is still worth trusting. Each check is a cheap local
-- lookup (PATH, env var or file stat) -- no network beyond ollama's own
-- cached probe above -- and reads the check straight from codecompanion's
-- own adapter tables instead of hardcoding per-provider knowledge.

local function acp_adapter_available(name)
    local ok, adapter = pcall(require, "codecompanion.adapters.acp." .. name)
    if not ok or type(adapter) ~= "table" then
        return false
    end
    local cmd = adapter.commands and adapter.commands.default and adapter.commands.default[1]
    return type(cmd) == "string" and vim.fn.executable(cmd) == 1
end

local function http_env_available(name)
    local ok, adapter = pcall(require, "codecompanion.adapters.http." .. name)
    if not ok or type(adapter) ~= "table" or type(adapter.env) ~= "table" then
        return false
    end
    for _, var in pairs(adapter.env) do
        if type(var) == "string" and vim.env[var] and vim.env[var] ~= "" then
            return true
        end
    end
    return false
end

-- Mirrors codecompanion's own `adapters/http/copilot/token.lua` lookup, but
-- only as far as checking a token file exists -- we don't need the token
-- itself, just a signal that Copilot has been authenticated on this machine.
local function copilot_available()
    if os.getenv("GITHUB_TOKEN") and os.getenv("CODESPACES") then
        return true
    end

    local config_path = os.getenv("CODECOMPANION_TOKEN_PATH")
    if not config_path then
        local xdg = vim.fs.normalize("$XDG_CONFIG_HOME")
        if xdg ~= "" and vim.fn.isdirectory(xdg) > 0 then
            config_path = xdg
        elseif vim.fn.has("win32") > 0 then
            config_path = vim.fs.normalize("~/AppData/Local")
        else
            config_path = vim.fs.normalize("~/.config")
        end
    end
    if not config_path or vim.fn.isdirectory(config_path) == 0 then
        return false
    end

    -- hosts.json/apps.json are the file-based auth methods; auth.db is the
    -- SQLite-backed one some setups use instead. Existence alone is enough
    -- as an availability signal -- we don't need to actually read the token.
    for _, file in ipairs({ "hosts.json", "apps.json", "auth.db" }) do
        if vim.uv.fs_stat(vim.fs.joinpath(config_path, "github-copilot", file)) then
            return true
        end
    end
    return false
end

-- Curated shortlist: broad enough to cover the common self-hosted/paid
-- coding-agent options, small enough that <leader>cn never turns into noise.
-- Extend this list to add more -- everything else about detection is generic.
local CHAT_PROVIDERS = {
    { name = "ollama", label = "Ollama (self-hosted)", available = ollama_reachable },
    { name = "claude_code", label = "Claude Code", available = function() return acp_adapter_available("claude_code") end },
    { name = "codex", label = "Codex", available = function() return acp_adapter_available("codex") end },
    { name = "cursor_cli", label = "Cursor", available = function() return acp_adapter_available("cursor_cli") end },
    { name = "copilot", label = "GitHub Copilot", available = copilot_available },
    { name = "openrouter", label = "OpenRouter", available = function() return http_env_available("openrouter") end },
}

---Whether `adapter_name` currently looks usable. Adapters outside the
---curated list (e.g. reached manually via `:CodeCompanionChat`) are trusted,
---since we have no cheap way to probe them.
---@param adapter_name string
---@return boolean
local function provider_valid(adapter_name)
    for _, provider in ipairs(CHAT_PROVIDERS) do
        if provider.name == adapter_name then
            return provider.available()
        end
    end
    return true
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
        local ok, err = pcall(function()
            local chat = Chat.buf_get_chat((args.data or {}).bufnr)
            if not chat or chat.status ~= "success" or not chat.adapter or type(chat.adapter.name) ~= "string" then
                return
            end

            local model = selected_model(chat)
            chat_state.adapter = chat.adapter.name
            if type(model) == "string" and model ~= "" then
                chat_state.models[chat_state.adapter] = model
            end
            save_chat_state()
        end)
        if not ok then
            vim.notify("Could not remember CodeCompanion chat defaults: " .. tostring(err), vim.log.levels.WARN)
        end
    end,
})

---The session file mini.sessions (or the repo-local Session.vim path handled
---in mini-sessions.lua) most recently loaded, if any -- both set `v:this_session`.
---@return string|nil
local function session_key()
    local key = vim.v.this_session
    return (key ~= nil and key ~= "") and key or nil
end

---Which adapter/model to reopen for "last used": this session's own
---remembered pair if one was loaded and it still checks out, else whatever
---was last successful globally. A stale session entry is left as-is here --
---it gets overwritten with the global values by the next VimLeavePre save.
---@return string, string|nil
local function resolve_last_chat()
    local key = session_key()
    if key then
        local entry = chat_state.sessions[key]
        if entry and type(entry.adapter) == "string" and provider_valid(entry.adapter) then
            return entry.adapter, entry.model
        end
    end
    return chat_state.adapter, chat_state.models[chat_state.adapter]
end

vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Remember this session's last-used CodeCompanion adapter/model",
    callback = function()
        local ok = pcall(function()
            local key = session_key()
            if not key or not chat_state.adapter then
                return
            end
            chat_state.sessions[key] = {
                adapter = chat_state.adapter,
                model = chat_state.models[chat_state.adapter],
            }
            save_chat_state()
        end)
        if not ok then
            vim.notify("Could not remember this session's CodeCompanion defaults", vim.log.levels.WARN)
        end
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

local function open_chat_with(adapter_name, model, force_new)
    if adapter_name and not provider_valid(adapter_name) then
        return
    end

    local host = host_win()
    local chat = not force_new and adapter_name and find_chat(adapter_name, model)

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

    -- No chat for this adapter/model pair yet. With no adapter_name at all
    -- (no memory yet -- first-ever chat), fall back to codecompanion's own
    -- configured default instead of guessing one.
    local command = "CodeCompanionChat"
    if adapter_name then
        command = command .. " adapter=" .. vim.fn.fnameescape(adapter_name)
        if model then
            command = command .. " model=" .. vim.fn.fnameescape(model)
        end
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

---Always starts a new chat for `adapter_name`, using that adapter's own
---remembered model. Used by the <leader>cn picker.
---@param adapter_name string
local function open_named_chat(adapter_name)
    open_chat_with(adapter_name, chat_state.models[adapter_name], true)
end

---Reopens (or creates) the last-successful chat -- see `resolve_last_chat`.
local function open_last_chat()
    local adapter_name, model = resolve_last_chat()
    open_chat_with(adapter_name, model, false)
end

local function pick_new_chat()
    local candidates = vim.iter(CHAT_PROVIDERS):filter(function(p) return p.available() end):totable()
    if vim.tbl_isempty(candidates) then
        vim.notify("No CodeCompanion providers are currently available", vim.log.levels.WARN)
        return
    end

    vim.ui.select(candidates, {
        prompt = "New CodeCompanion chat:",
        format_item = function(p) return p.label end,
    }, function(choice)
        if choice then
            open_named_chat(choice.name)
        end
    end)
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

vim.keymap.set({ "n", "v" }, "<leader>cc", open_last_chat,
    { noremap = true, desc = "CodeCompanion chat (last successful provider/model)" })
vim.keymap.set({ "n", "v" }, "<leader>cn", pick_new_chat,
    { noremap = true, desc = "CodeCompanion new chat (choose provider)" })
vim.api.nvim_set_keymap('n', '<leader>ch',
    '<cmd>CodeCompanionHistory<CR>',
    { noremap = true, silent = true, desc = "CodeCompanion chat history" })
