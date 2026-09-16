# nvim

Personal Neovim configuration. Plugins are tracked as git submodules under
`pack/*/start` (Neovim's native package loading — no plugin manager).

## Prerequisites

Only two, because [`install/`](install/README.md) handles the rest:

- **Neovim 0.12+** — the pinned `nvim-treesitter` submodule is the `main`
  rewrite, which requires it
- **Git**

Everything else — the C compiler and `tree-sitter-cli` that build the parsers,
ripgrep and fd for Telescope, Node and Python for the Mason packages,
ImageMagick for inline images, the `jupytext` CLI, the Neovim venv that molten
runs in, the language servers and debug adapters — is installed by
`install/install.sh` (or `install.ps1` on Windows). Run
`nvim -l install/install.lua --tree` to see the full list and what needs what.

Optional, and off unless you ask for them (`--with=ollama`, or `--all`):

- **Ollama**, running locally, for CodeCompanion's default chat adapter
  (`ollama pull gpt-oss:20b` gives it a model)
- **Claude Code CLI** (`claude` on `PATH`) for CodeCompanion's `claude_code`
  agent
- **`gh` CLI** for opening links from CodeCompanion chat history
- **verible** and **verilator** for SystemVerilog
- **A Nerd Font** for `nvim-web-devicons` and `lualine` icons

Two things no installer can do for you: use a terminal that implements the
Kitty graphics protocol (Ghostty, Kitty, WezTerm) if you want image.nvim to
draw plots, and point your terminal at the Nerd Font once it is installed.

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

## Keymaps

See [REMAPS.md](REMAPS.md) for the full cheatsheet.
