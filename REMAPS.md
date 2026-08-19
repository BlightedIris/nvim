# Keymap cheatsheet

Leader is `<Space>`. This page is organised by **what you want to do**, not by
which plugin provides it. The "Source" column says where the mapping is
defined so you can tweak it or read that plugin's docs for the full feature
set.

- `lua/ricardo/remaps.lua` — everything hand-rolled
- `lua/plugins/mini-*.lua` — one file per mini.nvim module
- `lua/plugins/codecompanion.lua` — AI chat mappings (defined there because
  they depend on that plugin's setup)

## Move around

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | n | Focus window left/down/up/right | remaps |
| `{N}<C-w>w` | n | Jump to window `N` (numbers shown in the lualine winbar) | native |
| `<C-d>` / `<C-u>` | n | Half-page down/up, cursor stays centered (`zz`) | remaps |
| `n` / `N` | n | Next/previous search match, centered and unfolded (`zzzv`) | remaps |
| `[b` / `]b` | n | Previous / next buffer | [mini.bracketed] |
| `[j` / `]j` | n | Previous / next jumplist entry | [mini.bracketed] |
| `[o` / `]o` | n | Previous / next file in the oldfiles list | [mini.bracketed] |
| `[w` / `]w` | n | Previous / next window | [mini.bracketed] |
| `[i` / `]i` | n | Previous / next indent change | [mini.bracketed] |
| `[t` / `]t` | n | Previous / next tree-sitter sibling node | [mini.bracketed] |
| `[c` / `]c` | n | Previous / next comment block | [mini.bracketed] |
| `[x` / `]x` | n | Previous / next conflict marker | [mini.bracketed] |
| `g[` / `g]` + object | n | Jump to start / end of a text object | [mini.ai] |

`[`/`]` + suffix jumps backward/forward; the **uppercase** suffix jumps to the
first/last target instead (e.g. `]B` = last buffer).

## Find things

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `<leader>ff` | n | Find files by name | [telescope] |
| `<leader>fg` | n | Live grep across the project | [telescope] |
| `<leader>fb` | n | List open buffers | [telescope] |
| `<leader>gs` / `gs` | n | Document symbols | [telescope] |
| `<leader>gw` | n | Workspace symbols | [telescope] |
| `<leader>d` | n | Toggle the file tree | [neo-tree] |

Requires `rg` and `fd` on `PATH`.

## Understand code

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `K` | n | Hover documentation | LSP |
| `gd` | n | Go to definition | LSP + [telescope] |
| `gi` | n | Go to implementation | LSP + [telescope] |
| `gr` | n | Find references | LSP + [telescope] |
| `gy` | n | Type definition — "what type is this?" | LSP |
| `gci` | n | Incoming calls — "who calls this?" | LSP |
| `gco` | n | Outgoing calls — "what does this call?" | LSP |

## Fix & refactor

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `<leader>ca` | n | Code action (quick fixes, refactors) | LSP |
| `<leader>rn` | n | Rename symbol | LSP |
| `<C-s>` | n | Format buffer | LSP |

## Diagnostics

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `[D` / `]D` | n | Previous / next diagnostic in the file | remaps |
| `[d` / `]d` | n | Previous / next diagnostic (bracketed family) | [mini.bracketed] |
| `[q` / `]q` | n | Previous / next quickfix entry | [mini.bracketed] |
| `[l` / `]l` | n | Previous / next location-list entry | [mini.bracketed] |

`virtual_text` is off; diagnostics pop up in a float after 250ms idle
(`updatetime` + `CursorHold` autocmd in `init.lua`). The uppercase `[D`/`]D`
exist so mini.bracketed keeps the lowercase pair in its `[`/`]` + suffix
family.

## Edit text

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `J` / `K` | v | Move selected lines down / up (reindent, keep selection) | remaps |
| `sa` + motion + char | n, v | Add surrounding (`saiw"` quotes a word) | [mini.surround] |
| `sd` + char | n | Delete surrounding (`sd(`) | [mini.surround] |
| `sr` + old + new | n | Replace surrounding (`sr"'`) | [mini.surround] |
| `sf` / `sF` + char | n | Find surrounding right / left | [mini.surround] |
| `sh` + char | n | Highlight surrounding | [mini.surround] |
| `ga` + motion | n, v | Align text into columns | [mini.align] |
| `gA` + motion | n, v | Align with interactive preview | [mini.align] |
| `gS` | n, v | Toggle one-line ⇄ multi-line arguments/blocks | [mini.splitjoin] |
| `[u` / `]u` | n | Previous / next undo state | [mini.bracketed] |
| `[y` / `]y` | n | Cycle the last paste through the yank history | [mini.bracketed] |

### Select a chunk of code (text objects)

Work with any operator (`d`, `c`, `y`, `v`, …), searching up to 500 lines away.

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `af` / `if` | o, v | Around / inside a function call | [mini.ai] |
| `aa` / `ia` | o, v | Around / inside an argument | [mini.ai] |
| `aq` / `iq` | o, v | Around / inside any quote | [mini.ai] |
| `ab` / `ib` | o, v | Around / inside any bracket | [mini.ai] |
| `a?` / `i?` | o, v | Prompt for custom start/end delimiters | [mini.ai] |
| `an` / `in` + object | o, v | Target the **next** object (e.g. `dinq`) | [mini.ai] |
| `al` / `il` + object | o, v | Target the **last** object | [mini.ai] |

## Complete code as I type

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `<C-Space>` | i | Show completion menu / documentation | [blink.cmp] |
| `<Tab>` | i | Accept selection (falls through if nothing selected) | [blink.cmp] |
| `<CR>` | i | Accept selection (falls through if nothing selected) | [blink.cmp] |

Sources: LSP, CodeCompanion, path, buffer, and Minuet (Ollama-backed FIM ghost
text, prioritized via `score_offset`).

## Ask an AI

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `<leader>co` | n, v | Open/focus the Ollama chat (`gpt-oss:20b`) | [codecompanion] |
| `<leader>cc` | n, v | Open/focus the Claude Code ACP chat | [codecompanion] |
| `<leader>cno` | n, v | Always start a **new** Ollama chat | [codecompanion] |
| `<leader>cnc` | n, v | Always start a **new** Claude Code chat | [codecompanion] |
| `<leader>ch` | n | Browse saved chats (`:CodeCompanionHistory`) | [codecompanion] |
| `<leader>cd` | n | Delete saved chats (`<Tab>` marks, `<Enter>` deletes) | remaps |
| `<leader>cda` | n | Delete *all* saved chats (prompts to confirm) | remaps |
| `<leader>cr` | n | `:CodeCompanionRestart` | remaps |
| `}` / `{` | n | Cycle between already-open chats (inside a chat buffer) | [codecompanion] |
| `?` | n | Full chat-buffer reference (keymaps, tools, variables) | [codecompanion] |

`<leader>co`/`<leader>cc` focus an existing chat for that adapter rather than
spawning a new buffer (plain `:CodeCompanionChat` always creates one, silently
abandoning in-progress drafts). Use `<leader>cno`/`<leader>cnc` when you
actually want a second, independent conversation.

## Buffers, sessions & terminals

| Keys | Mode | Action | Source |
| --- | --- | --- | --- |
| `<leader>bd` | n | Delete the current buffer, preserving window layout | [mini.bufremove] |
| `<leader>bD` | n | Force delete the buffer (discards unsaved changes) | [mini.bufremove] |
| `<leader>ss` | n | Write / overwrite a named session | [mini.sessions] |
| `<leader>sl` | n | Load a session | [mini.sessions] |
| `<leader>sx` | n | Delete a session | [mini.sessions] |
| `<leader>t` | n | Open a terminal (PowerShell on Windows, `$SHELL` elsewhere) | remaps |
| `<Esc>` | t | Leave terminal insert mode (`<C-\><C-n>`) | remaps |
| `<leader>?` | n | Open this cheatsheet | remaps |

Sessions live in `stdpath('data')/sessions`. `autowrite` is on (saved on
exit); `autoread` is off, so startup is never hijacked.

Starting `nvim` with no file argument opens a fixed three-pane layout:
Neo-tree left, editor over terminal in the middle, Ollama chat on the right
(`lua/ricardo/gui_setup.lua`). Passing a file skips this.

<!-- Plugin docs -->

[mini.ai]: pack/basics/start/mini.ai/README.md
[mini.align]: pack/basics/start/mini.align/README.md
[mini.bracketed]: pack/basics/start/mini.bracketed/README.md
[mini.bufremove]: pack/basics/start/mini.bufremove/README.md
[mini.sessions]: pack/basics/start/mini.sessions/README.md
[mini.splitjoin]: pack/basics/start/mini.splitjoin/README.md
[mini.surround]: pack/basics/start/mini.surround/README.md
[neo-tree]: pack/basics/start/neo-tree-nvim/README.md
[telescope]: pack/basics/start/telescope/README.md
[blink.cmp]: pack/basics/start/blink-cmp/README.md
[codecompanion]: pack/basics/start/codecompanion-nvim/README.md
