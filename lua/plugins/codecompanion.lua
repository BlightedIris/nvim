-- Ollama's gpt-oss:20b doesn't reliably follow the ask_questions tool schema --
-- it sometimes sends each question as a plain string (or each option as a
-- plain string) instead of the required {header=..., question=...} table.
-- question_prompt.lua then does `table.concat` over a line list containing a
-- nil, which throws before the question ever renders and before any of the
-- reply/skip keymaps get bound -- so the question is invisible and replying
-- errors. Normalize malformed shapes before the tool runs.
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
            -- Ollama's default keep_alive (5m) unloads the model between
            -- edits, causing a cold-load stall on the next request.
            keep_alive = { default = "30m" },
            -- Explicit cap instead of the model's full 32K trained context --
            -- keeps chat/inline VRAM use predictable. (The OLLAMA_CONTEXT_LENGTH
            -- env var does NOT work here: Ollama's Windows tray app hardcodes
            -- its own value internally and ignores what launches it with.)
            -- 8192 was too small for @agent tool use: once the system prompt +
            -- tool schemas + tool output (file reads, command output) pushed
            -- the prompt past num_ctx, llama.cpp silently shifted/dropped the
            -- oldest context, which showed up as the model "forgetting" the
            -- whole conversation mid-chat.
            num_ctx = { default = 16384 },
          },
        })
      end,
    },
  },
  interactions = {
    chat = {
      adapter = "ollama",
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
    -- Persists chats across restarts. `gh` in a chat buffer (or
    -- :CodeCompanionHistory) opens the browser; picker defaults to telescope,
    -- which is already installed.
    history = {
      enabled = true,
    },
  },
})

-- Explicit adapter selection (never auto-routed). Focuses an already-open
-- chat for that adapter instead of always creating a new buffer -- plain
-- `:CodeCompanionChat` does that unconditionally, which was silently
-- abandoning in-progress drafts (and then reporting "No messages to submit"
-- on the new, empty buffer).
local function open_chat(adapter_name)
  local Chat = require("codecompanion.interactions.chat")
  for _, entry in ipairs(Chat.buf_get_chat()) do
    if entry.chat.adapter and entry.chat.adapter.name == adapter_name then
      if entry.chat.ui:is_visible() then
        vim.api.nvim_set_current_win(entry.chat.ui.winnr)
      else
        entry.chat.ui:open()
      end
      return
    end
  end
  vim.cmd("CodeCompanionChat adapter=" .. adapter_name)
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

vim.keymap.set({ "n", "v" }, "<leader>co", function() open_chat("ollama") end, { noremap = true, desc = "CodeCompanion chat (Ollama)" })
vim.keymap.set({ "n", "v" }, "<leader>cc", function() open_chat("claude_code") end, { noremap = true, desc = "CodeCompanion chat (Claude Code ACP)" })
vim.api.nvim_set_keymap('n', '<leader>ch',
  '<cmd>CodeCompanionHistory<CR>',
  { noremap = true, silent = true, desc = "CodeCompanion chat history" })


