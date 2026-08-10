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
            num_ctx = { default = 8192 },
          },
        })
      end,
    },
  },
  interactions = {
    chat = {
      adapter = "ollama",
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

vim.keymap.set({ "n", "v" }, "<leader>ao", function() open_chat("ollama") end, { noremap = true, desc = "CodeCompanion chat (Ollama)" })
vim.keymap.set({ "n", "v" }, "<leader>ac", function() open_chat("claude_code") end, { noremap = true, desc = "CodeCompanion chat (Claude Code ACP)" })

