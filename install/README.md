# Installer

Install Neovim, clone this repo, run one command, edit.

```bash
# Linux / macOS
git clone --recurse-submodules https://github.com/BlightedIris/nvim.git ~/.config/nvim
~/.config/nvim/install/install.sh
```

```powershell
# Windows
git clone --recurse-submodules https://github.com/BlightedIris/nvim.git $env:LOCALAPPDATA\nvim
& $env:LOCALAPPDATA\nvim\install\install.ps1
```

Neither script needs the repo to exist first — piping them from a raw URL works
too, and they will clone it for you:

```bash
curl -fsSL https://raw.githubusercontent.com/BlightedIris/nvim/main/install/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/BlightedIris/nvim/main/install/install.ps1 | iex
```

## What runs what

The bootstrap scripts are deliberately tiny. They install **git** and
**Neovim ≥ 0.12**, make sure the config is checked out, and then get out of the
way:

```
install.sh  ─┐
             ├─►  nvim -l install/install.lua  ──►  everything else
install.ps1 ─┘
```

The installer proper is Lua, run by Neovim itself (`nvim -l` is a plain Lua
interpreter with `vim.system`, `vim.uv`, `vim.fs` and `vim.json` attached).
That is the one interpreter guaranteed to be present on every machine this
config lands on, so there is one implementation of the real logic rather than
two that drift apart.

## Usage

```
nvim -l install/install.lua [options]

  --check         Report what is present and what is missing; change nothing
                  (exits non-zero when something required is absent)
  --tree          Print the dependency tree and exit
  --dry-run       Say what would be installed without installing it
  -y, --yes       Do not ask for confirmation
  --all           Include every optional component
  --with=a,b      Include specific optional components
  --skip=a,b      Skip these components
  --only=a,b      Install only these (their requirements come along)
  --no-color      Plain output
```

Options given to `install.sh` / `install.ps1` are passed straight through.

The run is idempotent: every component is probed before it is touched, so
re-running only picks up what is still missing. Optional components are opt-in
(`--with=ollama`, or `--all`).

---

# How the list was built

Four passes, in order.

## 1. Information gathering

Everything external the config reaches for, and where that shows up:

| Need | Evidence |
| --- | --- |
| Neovim 0.12+ | `pack/basics/start/tree-sitter/README.md` — the pinned nvim-treesitter is the `main` rewrite |
| git | 39 plugin submodules under `pack/*/start`; Mason clones some packages |
| C compiler, `tree-sitter-cli` ≥ 0.26.1 | nvim-treesitter requirements; `lua/plugins/treesitter.lua` asks for 49 parsers |
| ripgrep, fd | `lua/ricardo/remaps.lua` Telescope `live_grep` / `find_files` |
| Node + npm | Mason installs `bash-language-server`, `svlangserver`, `basedpyright` from npm |
| Python 3.10+ | molten's host interpreter, `debugpy`, `jupytext` |
| LSP servers, DAP adapters, shellcheck/shfmt | `lua/plugins/mason-lspconfig.lua`, `lua/plugins/dap.lua`, `lua/plugins/mason.lua` |
| verible, verilator | `lua/plugins/lsp.lua` gates `verible` on `verible-verilog-ls`; svlangserver shells out to verilator for lint |
| ImageMagick | `lua/plugins/image.lua` sets `processor = 'magick_cli'` |
| `jupytext` CLI | `lua/plugins/jupytext.lua` |
| pynvim, jupyter_client, ipykernel, … | molten is a remote plugin; `init.lua` documents the venv and its packages |
| Rust (nightly) | `lua/plugins/blink.lua` sets `fuzzy.implementation = 'rust'`; `pack/basics/start/blink-cmp/rust-toolchain.toml` pins nightly |
| Ollama, `claude`, `gh` | `lua/plugins/codecompanion.lua`, `lua/ricardo/gui_setup.lua` (curls `localhost:11434`) |
| pwsh | `lua/plugins/lsp.lua` only enables `powershell_es` where a PowerShell exists |
| Nerd Font, kitty-graphics terminal | `nvim-web-devicons` / `lualine`; image.nvim's `kitty` backend |

Things deliberately **not** in the list: the Quarto CLI is optional, because
`lua/plugins/quarto.lua` says outright that nothing here renders or previews
Quarto documents — otter and the cell runner do not need it.

## 2. Pruning

Deduplicated, then sorted into a tree. It has several roots, which is fine —
they all have to be installed anyway.

```
git ──────────► submodules ──┬─► blink-fuzzy   (+ rust)
                             ├─► treesitter-parsers (+ tree-sitter-cli, cc, curl)
                             ├─► mason-packages (+ node, python, curl, archive-tools)
                             └─► remote-plugins (+ nvim-venv)

neovim ───────► cc ─────────► tree-sitter-cli
python ───┬───► nvim-venv
uv ───────┘
          └───► jupytext
rust ─────────► ripgrep / fd fallbacks, blink-fuzzy
curl, archive-tools ────────► verible
node ─────────► claude
imagemagick ──► ghostscript
```

`nvim -l install/install.lua --tree` prints the current version of this, since
the tree is data in `lib/manifest.lua` rather than prose.

The ordering matters in three places, and only three:

- **submodules before everything repo-side.** Mason, the parsers and the blink
  build all live inside plugins that are submodules.
- **tree-sitter-cli and a C compiler before parsers.** Parsers are compiled
  from source at install time.
- **the venv before `:UpdateRemotePlugins`.** The manifest is generated by
  running molten in the host interpreter, which needs `pynvim` present.

That tree is also what picked the language: the root is Neovim, and every
branch below it is reachable from `nvim -l`.

## 3. Sourcing

One row per component, one column per platform. `lib/manifest.lua` holds this
as data; the fallback column is what runs when the package manager has no such
package (or ships one too old to use).

| Component | Arch | Debian/Ubuntu | Fedora | macOS | Windows | Fallback |
| --- | --- | --- | --- | --- | --- | --- |
| git | `git` | `git` | `git` | `git` | `Git.Git` | — |
| curl | `curl` | `curl` | `curl` | `curl` | `cURL.cURL` | — |
| neovim | `neovim` | — | — | `neovim` | `Neovim.Neovim` | official release tarball |
| cc | `gcc` | `build-essential` | `gcc` | `xcode-select --install` | `zig.zig` | — |
| archive-tools | `tar unzip gzip` | same | same | `unzip` | `7zip.7zip` | — |
| node | `nodejs npm` | `nodejs npm` | `nodejs` | `node` | `OpenJS.NodeJS.LTS` | — |
| python | `python` | `python3 python3-venv python3-pip` | `python3 python3-pip` | `python` | `Python.Python.3.12` | — |
| rust | `rustup` | — | — | `rustup` | `Rustlang.Rustup` | `sh.rustup.rs` |
| uv | `uv` | — | `uv` | `uv` | `astral-sh.uv` | `astral.sh/uv/install.sh` |
| ripgrep | `ripgrep` | `ripgrep` | `ripgrep` | `ripgrep` | `BurntSushi.ripgrep.MSVC` | `cargo install ripgrep` |
| fd | `fd` | `fd-find` † | `fd-find` † | `fd` | `sharkdp.fd` | `cargo install fd-find` |
| tree-sitter-cli | `tree-sitter-cli` | — | `tree-sitter-cli` | `tree-sitter` | — | GitHub release, then cargo |
| imagemagick | `imagemagick` | `imagemagick` | `ImageMagick` | `imagemagick` | `ImageMagick.ImageMagick` | — |
| ghostscript | `ghostscript` | `ghostscript` | `ghostscript` | `ghostscript` | `ArtifexSoftware.GhostScript` | — |
| jupytext | — | — | — | — | — | `uv tool install jupytext` |
| verilator | `verilator` | `verilator` | `verilator` | `verilator` | — (use WSL) | — |
| verible | — | — | — | — | — | GitHub release → `~/.local/bin` |
| ollama | `ollama` | — | — | `ollama` | `Ollama.Ollama` | `ollama.com/install.sh` |
| claude | — | — | — | — | — | `npm i -g @anthropic-ai/claude-code` |
| gh | `github-cli` | `gh` | `gh` | `gh` | `GitHub.cli` | — |
| pwsh | — | — | — | `cask:powershell` | built in | — |
| quarto | — | — | — | `cask:quarto` | `Posit.Quarto` | GitHub release |
| nerd-font | `ttf-jetbrains-mono-nerd` | — | — | `cask:font-…` | — | GitHub release → font dir |

† Debian and Fedora install the binary as `fdfind`; the installer symlinks
`~/.local/bin/fd` to it, because Telescope looks for `fd` first.

Repo-side components have no package anywhere — they are steps:

| Step | Source |
| --- | --- |
| submodules | `git submodule update --init --recursive` |
| nvim-venv | `uv venv ~/.local/share/nvim/venv` + the package list from `init.lua` |
| blink-fuzzy | `cargo build --release`, then the checked-out SHA written to `target/release/version` |
| treesitter-parsers | `nvim-treesitter.install(<languages>)` |
| mason-packages | `:MasonInstall` for everything the config ensures |
| remote-plugins | `:UpdateRemotePlugins` |

## 4. Building

```
install/
  install.sh      bootstrap: git + Neovim, clone, hand over
  install.ps1     the same, for Windows
  install.lua     entry point: options, topological sort, run, report
  lib/log.lua     terminal output and prompts
  lib/sys.lua     exec, platform detection, downloads, archives, versions
  lib/pm.lua      the system package manager behind one interface
  lib/manifest.lua the dependency tree and every source (the table above)
  lib/steps.lua   the steps that act on the checkout itself
```

Adding a dependency means adding one entry to `lib/manifest.lua` — a `check`,
its `requires`, and wherever it comes from. Nothing else in the installer needs
to know about it.

Two details in `lib/steps.lua` are worth knowing about, because both are easy
to get wrong:

- Steps that need the real config run a nested `nvim --headless` **with a dummy
  file argument**. `lua/plugins/mini-sessions.lua` treats `argc() > 0` as "quick
  edit, not a session", which stops each headless run from restoring a session
  on entry and, more importantly, from overwriting a saved one on exit.
- The parser step runs in a *bare* Neovim (`--clean -l`) instead, because
  loading the config starts its own asynchronous install of the same parsers
  and the two would race. It borrows the language list from
  `lua/plugins/treesitter.lua` by stubbing the module that file calls, so the
  list never has to be duplicated here.

## Things the installer cannot do for you

- **A terminal that speaks the Kitty graphics protocol** (Ghostty, Kitty,
  WezTerm) — image.nvim draws plots and inline markdown images through it.
- **Setting your terminal font** to the Nerd Font it installs.
- **Pulling an Ollama model.** `ollama pull gpt-oss:20b` gives CodeCompanion's
  default chat adapter something to talk to.
- **Windows and molten.** `init.lua` points `g:python3_host_prog` at
  `~/.local/share/nvim/venv/bin/python`, a POSIX path. On Windows the venv the
  installer creates lands at `~/AppData/Local/nvim-data/venv/Scripts/python.exe`
  and `init.lua` will not find it; the installer says so when it runs there.
