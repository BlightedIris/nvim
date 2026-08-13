# Keymap cheatsheet

Leader is `<Space>` (set in `init.lua`). Custom mappings live in
`lua/ricardo/remaps.lua`; CodeCompanion's own mappings live at the bottom of
`lua/plugins/codecompanion.lua` since they depend on that plugin's setup.

## Navigation & windows

| Keys | Mode | Action |
| --- | --- | --- |
| `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | n | Move focus to the window left/down/up/right |
| `<leader>d` | n | Toggle Neo-tree |
| `<leader>t` | n | Open a terminal split (PowerShell on Windows, `$SHELL` elsewhere) |
| `<Esc>` | t | Leave terminal insert mode (`<C-\><C-n>`) |
| `<leader>?` | n | Open this cheatsheet (`REMAPS.md`, resolved via `stdpath('config')`) |

The lualine winbar shows each window's number (`{N}<C-w>w` jumps straight to
it) — that's native Neovim, not a custom mapping (`lua/plugins/lualine.lua`).

## Editing

| Keys | Mode | Action |
| --- | --- | --- |
| `J` | v | Move the selected lines down one line (reindents, keeps selection) |
| `K` | v | Move the selected lines up one line (reindents, keeps selection) |

## Fuzzy finding (Telescope)

| Keys | Mode | Action |
| --- | --- | --- |
| `<leader>ff` | n | Find files |
| `<leader>fg` | n | Live grep |
| `<leader>fb` | n | List open buffers |
| `<leader>gc` | n | Git commits |
| `<leader>gb` | n | Git branches |
| `<leader>gw` | n | Workspace symbols |

## LSP

| Keys | Mode | Action |
| --- | --- | --- |
| `K` | n | Hover documentation |
| `gd` | n | Go to definition (Telescope picker) |
| `gi` | n | Go to implementation (Telescope picker) |
| `gr` | n | Find references (Telescope picker) |
| `gs` | n | Document symbols (Telescope picker) |
| `gy` | n | Type definition — "what type is this?" |
| `gci` | n | Incoming calls — "who calls this?" |
| `gco` | n | Outgoing calls — "what does this call?" |
| `<leader>ca` | n | Code action |
| `<leader>rn` | n | Rename symbol |
| `<C-s>` | n | Format buffer |
| `[d` / `]d` | n | Previous / next diagnostic |
| `<C-d>` / `<C-u>` | n | Half-page down/up, cursor stays centered (`zz`) |
| `n` / `N` | n | Next/previous search match, cursor stays centered and unfolded (`zzzv`) |

Diagnostics also auto-popup on hover after 250ms idle (`updatetime` +
`CursorHold` autocmd in `init.lua`) since `virtual_text` is disabled.

## Insert-mode completion (blink.cmp)

| Keys | Action |
| --- | --- |
| `<C-Space>` | Show completion menu / documentation |
| `<Tab>` | Accept selection (falls through if nothing selected) |
| `<CR>` | Accept selection (falls through if nothing selected) |

Sources: LSP, CodeCompanion, path, buffer, and Minuet (Ollama-backed FIM
ghost text, prioritized via `score_offset`).

## CodeCompanion (AI chat)

| Keys | Mode | Action |
| --- | --- | --- |
| `<leader>co` | n, v | Open/focus chat on the local Ollama adapter (`gpt-oss:20b`) |
| `<leader>cc` | n, v | Open/focus chat on the Claude Code ACP adapter |
| `<leader>cno` | n, v | Always start a **new** Ollama chat, even if one is already open |
| `<leader>cnc` | n, v | Always start a **new** Claude Code ACP chat, even if one is already open |
| `<leader>ch` | n | `:CodeCompanionHistory` — browse saved chats |
| `<leader>cd` | n | Open saved chats for deletion; `<Tab>` marks multiple chats, then `<Enter>` deletes them |
| `<leader>cda` | n | `:ChatClearAll` — delete *all* saved chats (prompts to confirm) |
| `<leader>cr` | n | `:CodeCompanionRestart` |

`<leader>co`/`<leader>cc` focus an already-open chat for that adapter instead
of always spawning a new buffer — plain `:CodeCompanionChat` creates a new
one unconditionally, which was silently abandoning in-progress drafts. Use
`<leader>cno`/`<leader>cnc` when you actually want a second, independent
chat (e.g. to start a fresh conversation while the first is still streaming
a response).

Inside a chat buffer, `}`/`{` cycle between chats that are already open —
they don't create new ones. `?` opens the full keymap/tools/variables
reference for the chat buffer itself.

On startup with no file argument (`nvim` with no args), Neovim opens a fixed
three-pane layout automatically: Neo-tree on the left, an empty editor over a
terminal in the middle, and an Ollama CodeCompanion chat on the right (see
`lua/ricardo/gui_setup.lua`). Passing a file (`nvim foo.lua`) skips this.
