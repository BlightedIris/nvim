# nvim

Personal Neovim configuration. Plugins are tracked as git submodules under
`pack/*/start` (Neovim's native package loading — no plugin manager).

## Prerequisites

- **Neovim 0.11+** (required by `vim.lsp.enable()` in `lua/plugins/lsp.lua`
  and by the main-branch `nvim-treesitter` submodule)
- **Git**
- **A C compiler on `PATH`** (MSVC/clang/gcc, or `zig cc`) — needed by
  treesitter to compile parsers on first launch
- **ripgrep** (`rg`) and **fd** — used by Telescope's `find_files`/`live_grep`
- **A Nerd Font** in your terminal — for `nvim-web-devicons`, `bufferline`,
  and `lualine` icons

Optional, for specific features:

- **Language servers** for whichever languages you edit: `gopls`,
  `rust-analyzer`, `clangd`, `basedpyright`, `lua-language-server`,
  `bash-language-server`, PowerShell Editor Services (`powershell_es`),
  `verible-verilog-ls` (see `lua/plugins/lsp.lua`)
- **Ollama**, running locally, for AI completion/chat:
  - `gpt-oss:20b` pulled for CodeCompanion's Ollama chat adapter
  - a custom `qwen2.5-coder-fim` model for Minuet's FIM completion, built
    from `qwen2.5-coder:7b` with a Modelfile that pins `num_ctx=2048`
    (see comments in `lua/plugins/minuet-ai.lua`)
- **Claude Code CLI** (`claude` on `PATH`) for CodeCompanion's `claude_code`
  chat adapter
- **`gh` CLI** for opening links from CodeCompanion chat history

## Install

Neovim looks for its config under `%LOCALAPPDATA%\nvim` on Windows. Clone
this repo straight into that path, pulling in the plugin submodules at the
same time:

```powershell
git clone --recurse-submodules https://github.com/BlightedIris/nvim.git $env:LOCALAPPDATA\nvim
```

If you already have it cloned without submodules (or they've gone out of
sync), fetch them separately:

```powershell
git submodule update --init --recursive
```

Then launch `nvim`. On first start, `nvim-treesitter` installs all parsers
listed in `lua/plugins/treesitter.lua` automatically.

To pull in submodule updates later:

```powershell
git submodule update --remote --merge
```
