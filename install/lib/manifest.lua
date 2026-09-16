-- The dependency tree, and where every node comes from.
--
-- One entry per external thing this config needs. `requires` is what builds
-- the tree -- install.lua topologically sorts these, so the order below is
-- for reading, not for execution.
--
-- Sourcing rules, in the order they are tried:
--   1. `packages`   -- the system package manager, by its own package name
--   2. `fallback`   -- an upstream installer, release tarball, or cargo/npm
--   3. `note`       -- nothing automatic exists; tell the user what to do
--
-- `optional = true` means the config runs without it (a feature degrades);
-- those are skipped unless --with=<name> or --all is passed.
local log = require('lib.log')
local pm = require('lib.pm')
local sys = require('lib.sys')

local M = {}

--- Shared installers -------------------------------------------------------

-- Drop a single binary into ~/.local/bin, which init.lua puts on PATH.
local function install_binary(src, name)
    local bin = sys.local_bin()
    sys.mkdirp(bin)
    local dest = vim.fs.joinpath(bin, name .. (sys.is_windows and '.exe' or ''))
    local ok = vim.uv.fs_copyfile(src, dest)
    if not ok then
        return false
    end
    if not sys.is_windows then
        vim.uv.fs_chmod(dest, 493) -- 0755
    end
    sys.prepend_path(bin)
    return true
end

-- Grab a release asset, unpack it, and hand the directory to `place`.
local function from_github(repo, patterns, place)
    local asset = sys.github_asset(repo, patterns)
    if not asset then
        log.err(('No matching %s release asset for this platform'):format(repo))
        return false
    end
    log.dim('release ' .. (asset.tag or '?') .. ': ' .. asset.name)
    local dir = sys.tempdir('release')
    local archive = vim.fs.joinpath(dir, asset.name)
    if not sys.download(asset.url, archive) then
        return false
    end
    if archive:match('%.gz$') and not archive:match('%.tar%.gz$') then
        -- a bare gzipped binary (tree-sitter ships these)
        if not sys.stream({ 'gzip', '-d', '-f', archive }) then
            return false
        end
        return place(dir, (archive:gsub('%.gz$', '')))
    end
    local out = vim.fs.joinpath(dir, 'unpacked')
    if not sys.extract(archive, out) then
        return false
    end
    return place(out, nil)
end

-- Find a file by name anywhere under `root`.
local function find_file(root, name)
    local hits = vim.fs.find(name, { path = root, type = 'file', limit = 1 })
    return hits[1]
end

local function pipe_to_shell(url, shell_argv)
    if not sys.has('curl') then
        log.err('curl is required for this installer')
        return false
    end
    local script = vim.fs.joinpath(sys.tempdir('installer'), 'install-script')
    if not sys.download(url, script) then
        return false
    end
    local argv = vim.deepcopy(shell_argv)
    argv[#argv + 1] = script
    return sys.stream(argv)
end

--- The nodes ---------------------------------------------------------------

--- @type table[]
M.nodes = {
    ----------------------------------------------------------------------
    -- Tier 0: the bootstrap trio. install.sh / install.ps1 put these in
    -- place before this script can run at all; the entries exist so
    -- --check and --tree tell the whole story.
    ----------------------------------------------------------------------
    {
        name = 'git',
        desc = 'clones this repo and its 39 plugin submodules; Mason uses it too',
        check = function() return sys.has('git') end,
        packages = {
            pacman = 'git', apt = 'git', dnf = 'git', zypper = 'git', apk = 'git',
            brew = 'git', winget = 'Git.Git',
        },
    },
    {
        name = 'curl',
        desc = 'downloads for Mason, treesitter parsers, and the Ollama probe',
        check = function() return sys.has('curl') end,
        packages = {
            pacman = 'curl', apt = 'curl', dnf = 'curl', zypper = 'curl', apk = 'curl',
            brew = 'curl', winget = 'cURL.cURL',
        },
    },
    {
        name = 'neovim',
        desc = 'the editor itself; 0.12+ is required by the pinned nvim-treesitter',
        check = function()
            -- We are running inside nvim, so this is really a version gate.
            return vim.fn.has('nvim-0.12') == 1
        end,
        packages = {
            pacman = 'neovim', brew = 'neovim', winget = 'Neovim.Neovim',
            apk = 'neovim',
        },
        fallback = function()
            log.warn('This Neovim is older than 0.12 -- nvim-treesitter (main) needs 0.12+')
            log.info('Install a current build from https://github.com/neovim/neovim/releases')
            return false
        end,
    },

    ----------------------------------------------------------------------
    -- Tier 1: toolchains. Everything below is built or fetched by one of
    -- these, so they go first.
    ----------------------------------------------------------------------
    {
        name = 'cc',
        desc = 'C compiler -- treesitter compiles every parser from source',
        requires = { 'neovim' },
        check = function()
            for _, name in ipairs({ 'cc', 'gcc', 'clang', 'cl', 'zig' }) do
                if sys.has(name) then
                    return true
                end
            end
            return false
        end,
        packages = {
            pacman = 'gcc',
            apt = 'build-essential',
            dnf = 'gcc',
            zypper = 'gcc',
            apk = 'build-base',
            -- zig cc is the least painful C toolchain to get on Windows and
            -- is explicitly supported by treesitter's build step
            winget = 'zig.zig',
        },
        fallback = function()
            if sys.is_mac then
                log.info('Triggering the Xcode command line tools installer')
                return sys.stream({ 'xcode-select', '--install' })
            end
            return false
        end,
        note = 'Install a C compiler (gcc/clang, MSVC Build Tools, or zig)',
    },
    {
        name = 'archive-tools',
        desc = 'tar/unzip -- Mason unpacks nearly every package it installs',
        check = function()
            if sys.is_windows then
                return sys.has('tar') -- ships with Windows 10+
            end
            return sys.has('tar') and sys.has('unzip')
        end,
        packages = {
            pacman = { 'tar', 'unzip', 'gzip' },
            apt = { 'tar', 'unzip', 'gzip' },
            dnf = { 'tar', 'unzip', 'gzip' },
            zypper = { 'tar', 'unzip', 'gzip' },
            apk = { 'tar', 'unzip', 'gzip' },
            brew = 'unzip',
            winget = '7zip.7zip',
        },
    },
    {
        name = 'node',
        desc = 'Node + npm -- Mason installs bash-language-server, svlangserver and basedpyright from npm',
        check = function() return sys.has('node') and sys.has('npm') end,
        packages = {
            pacman = { 'nodejs', 'npm' },
            apt = { 'nodejs', 'npm' },
            dnf = 'nodejs',
            zypper = { 'nodejs22', 'npm22' },
            apk = { 'nodejs', 'npm' },
            brew = 'node',
            winget = 'OpenJS.NodeJS.LTS',
        },
    },
    {
        name = 'python',
        desc = 'Python 3.10+ -- molten\'s host interpreter, debugpy, jupytext',
        check = function()
            local exe = sys.is_windows and 'python' or 'python3'
            if not sys.has(exe) then
                return false
            end
            return sys.version_at_least(sys.version_of({ exe, '--version' }), '3.10')
        end,
        packages = {
            pacman = 'python',
            apt = { 'python3', 'python3-venv', 'python3-pip' },
            dnf = { 'python3', 'python3-pip' },
            zypper = { 'python3', 'python3-pip' },
            apk = { 'python3', 'py3-pip' },
            brew = 'python',
            winget = 'Python.Python.3.12',
        },
    },
    {
        name = 'rust',
        desc = 'rustup -- builds blink.cmp\'s fuzzy matcher (its toolchain file pins nightly)',
        optional = true,
        check = function() return sys.has('cargo') end,
        packages = {
            -- Distro cargo ignores rust-toolchain.toml, so blink's nightly
            -- pin is only honoured through rustup. Prefer rustup everywhere
            -- it is packaged.
            pacman = 'rustup', brew = 'rustup', winget = 'Rustlang.Rustup',
            apk = 'rustup',
        },
        fallback = function()
            if sys.is_windows then
                log.info('Install Rust from https://rustup.rs')
                return false
            end
            log.info('Installing rustup from https://sh.rustup.rs')
            local ok = pipe_to_shell('https://sh.rustup.rs', { 'sh', '-s', '--', '-y', '--no-modify-path' })
            if ok then
                sys.prepend_path(vim.fs.joinpath(sys.home(), '.cargo', 'bin'))
            end
            return ok and sys.has('cargo')
        end,
        post = function()
            sys.prepend_path(vim.fs.joinpath(sys.home(), '.cargo', 'bin'))
            if sys.has('rustup') then
                -- blink's rust-toolchain.toml selects nightly; make sure it exists
                sys.stream({ 'rustup', 'toolchain', 'install', 'nightly' })
            end
            return true
        end,
        note = 'Without cargo, blink.cmp downloads a prebuilt fuzzy matcher at runtime instead',
    },
    {
        name = 'uv',
        desc = 'Python package/venv manager -- creates the Neovim venv and installs jupytext',
        check = function() return sys.has('uv') end,
        packages = {
            pacman = 'uv', brew = 'uv', winget = 'astral-sh.uv', apk = 'uv', dnf = 'uv',
        },
        fallback = function()
            if sys.is_windows then
                return sys.stream({
                    'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
                    'irm https://astral.sh/uv/install.ps1 | iex',
                })
            end
            local ok = pipe_to_shell('https://astral.sh/uv/install.sh', { 'sh' })
            sys.prepend_path(vim.fs.joinpath(sys.home(), '.local', 'bin'))
            return ok
        end,
        post = function()
            sys.prepend_path(sys.local_bin())
            sys.prepend_path(vim.fs.joinpath(sys.home(), '.cargo', 'bin'))
            return true
        end,
        note = 'Falls back to `python -m venv` + pip if uv is unavailable',
    },

    ----------------------------------------------------------------------
    -- Tier 2: the command line tools the config shells out to.
    ----------------------------------------------------------------------
    {
        name = 'ripgrep',
        desc = 'Telescope live_grep',
        requires = { 'rust' },
        check = function() return sys.has('rg') end,
        packages = {
            pacman = 'ripgrep', apt = 'ripgrep', dnf = 'ripgrep', zypper = 'ripgrep',
            apk = 'ripgrep', brew = 'ripgrep', winget = 'BurntSushi.ripgrep.MSVC',
        },
        fallback = function()
            if sys.has('cargo') then
                return sys.stream({ 'cargo', 'install', 'ripgrep' })
            end
            return false
        end,
    },
    {
        name = 'fd',
        desc = 'Telescope find_files',
        requires = { 'rust' },
        check = function() return sys.has('fd') or sys.has('fdfind') end,
        packages = {
            pacman = 'fd', apt = 'fd-find', dnf = 'fd-find', zypper = 'fd',
            apk = 'fd', brew = 'fd', winget = 'sharkdp.fd',
        },
        post = function()
            -- Debian/Ubuntu ship the binary as `fdfind`; Telescope looks for
            -- `fd` first, so give it one.
            if not sys.has('fd') and sys.has('fdfind') then
                local bin = sys.local_bin()
                sys.mkdirp(bin)
                local link = vim.fs.joinpath(bin, 'fd')
                if not sys.exists(link) then
                    vim.uv.fs_symlink(sys.which('fdfind'), link)
                    log.dim('linked fdfind -> ~/.local/bin/fd')
                end
                sys.prepend_path(bin)
            end
            return true
        end,
        fallback = function()
            if sys.has('cargo') then
                return sys.stream({ 'cargo', 'install', 'fd-find' })
            end
            return false
        end,
    },
    {
        name = 'tree-sitter-cli',
        desc = 'generates parsers for nvim-treesitter (0.26.1+, and explicitly NOT the npm build)',
        requires = { 'cc', 'rust' },
        check = function()
            if not sys.has('tree-sitter') then
                return false
            end
            local version = sys.version_of({ 'tree-sitter', '--version' })
            if not sys.version_at_least(version, '0.26.1') then
                log.warn(('tree-sitter %s is older than the required 0.26.1'):format(version or '?'))
                return false
            end
            return true
        end,
        packages = {
            pacman = 'tree-sitter-cli', brew = 'tree-sitter', dnf = 'tree-sitter-cli',
        },
        -- Distro packages lag badly here, so verify the version we just
        -- installed and fall through to a release binary when it is stale.
        verify_packages = true,
        fallback = function()
            local os_tag = sys.is_windows and 'windows' or (sys.is_mac and 'macos' or 'linux')
            local arch = sys.arch() == 'arm64' and 'arm64' or 'x64'
            local ok = from_github('tree-sitter/tree-sitter', {
                ('tree%-sitter%-%s%-%s%%.gz$'):format(os_tag, arch),
                ('tree%-sitter%-%s%-%s%%.zip$'):format(os_tag, arch),
            }, function(dir, single)
                local src = single or find_file(dir, 'tree-sitter' .. (sys.is_windows and '.exe' or ''))
                if not src then
                    return false
                end
                return install_binary(src, 'tree-sitter')
            end)
            if ok then
                return true
            end
            if sys.has('cargo') then
                log.info('Falling back to `cargo install tree-sitter-cli`')
                return sys.stream({ 'cargo', 'install', 'tree-sitter-cli', '--locked' })
            end
            return false
        end,
    },
    {
        name = 'imagemagick',
        desc = 'image.nvim\'s magick_cli processor -- plots and inline markdown images',
        check = function() return sys.has('magick') or (sys.has('convert') and sys.has('identify')) end,
        packages = {
            pacman = 'imagemagick', apt = 'imagemagick', dnf = 'ImageMagick',
            zypper = 'ImageMagick', apk = 'imagemagick', brew = 'imagemagick',
            winget = 'ImageMagick.ImageMagick',
        },
    },
    {
        name = 'ghostscript',
        desc = 'lets ImageMagick rasterise PDFs for image.nvim',
        optional = true,
        requires = { 'imagemagick' },
        check = function() return sys.has('gs') or sys.has('gswin64c') end,
        packages = {
            pacman = 'ghostscript', apt = 'ghostscript', dnf = 'ghostscript',
            zypper = 'ghostscript', apk = 'ghostscript', brew = 'ghostscript',
            winget = 'ArtifexSoftware.GhostScript',
        },
    },
    {
        name = 'jupytext',
        desc = 'converts .ipynb <-> markdown on read/write (jupytext.nvim)',
        requires = { 'uv', 'python' },
        check = function() return sys.has('jupytext') end,
        fallback = function()
            if sys.has('uv') then
                local ok = sys.stream({ 'uv', 'tool', 'install', 'jupytext' })
                sys.prepend_path(sys.local_bin())
                return ok and sys.has('jupytext')
            end
            if sys.has('pipx') then
                return sys.stream({ 'pipx', 'install', 'jupytext' })
            end
            local py = sys.is_windows and 'python' or 'python3'
            return sys.stream({ py, '-m', 'pip', 'install', '--user', 'jupytext' })
        end,
    },
    {
        name = 'verilator',
        desc = 'svlangserver runs it for SystemVerilog lint diagnostics',
        optional = true,
        check = function() return sys.has('verilator') end,
        packages = {
            pacman = 'verilator', apt = 'verilator', dnf = 'verilator',
            zypper = 'verilator', apk = 'verilator', brew = 'verilator',
        },
        note = 'No Windows build; use WSL for SystemVerilog linting',
    },
    {
        name = 'verible',
        desc = 'verible-verilog-ls -- SystemVerilog format/lint/navigation (lsp.lua gates on it)',
        optional = true,
        requires = { 'curl', 'archive-tools' },
        check = function() return sys.has('verible-verilog-ls') end,
        fallback = function()
            local patterns
            if sys.is_windows then
                patterns = { 'win64%.zip$' }
            elseif sys.is_mac then
                patterns = { 'macOS%.tar%.gz$', 'macos.*%.tar%.gz$' }
            else
                patterns = {
                    ('linux%%-static%%-%s%%.tar%%.gz$'):format(sys.arch()),
                    'linux%-static.*%.tar%.gz$',
                }
            end
            return from_github('chipsalliance/verible', patterns, function(dir)
                local bin = sys.local_bin()
                sys.mkdirp(bin)
                local copied = 0
                -- The tarball is <root>/bin/verible-*; copy the whole bin dir
                -- so verible-verilog-format and -lint come along with the LS.
                for name, type_ in vim.fs.dir(dir, { depth = 3 }) do
                    if type_ == 'file' and name:match('verible%-verilog') then
                        local src = vim.fs.joinpath(dir, name)
                        local base = vim.fs.basename(name)
                        if install_binary(src, (base:gsub('%.exe$', ''))) then
                            copied = copied + 1
                        end
                    end
                end
                if copied == 0 then
                    return false
                end
                log.dim(('installed %d verible binaries into %s'):format(copied, bin))
                return true
            end)
        end,
    },
    {
        name = 'ollama',
        desc = 'local model server for CodeCompanion\'s default chat adapter',
        optional = true,
        check = function() return sys.has('ollama') end,
        packages = {
            pacman = 'ollama', brew = 'ollama', winget = 'Ollama.Ollama',
        },
        fallback = function()
            if sys.is_linux then
                return pipe_to_shell('https://ollama.com/install.sh', { 'sh' })
            end
            return false
        end,
        note = 'CodeCompanion falls back to other adapters; the chat sidebar just stays closed',
    },
    {
        name = 'claude',
        desc = 'Claude Code CLI -- CodeCompanion\'s claude_code agent shells out to it',
        optional = true,
        requires = { 'node' },
        check = function() return sys.has('claude') end,
        fallback = function()
            return sys.stream({ 'npm', 'install', '-g', '@anthropic-ai/claude-code' })
        end,
    },
    {
        name = 'gh',
        desc = 'GitHub CLI -- opening links from CodeCompanion chat history',
        optional = true,
        check = function() return sys.has('gh') end,
        packages = {
            pacman = 'github-cli', apt = 'gh', dnf = 'gh', zypper = 'gh',
            apk = 'github-cli', brew = 'gh', winget = 'GitHub.cli',
        },
    },
    {
        name = 'powershell',
        desc = 'powershell_es only starts where pwsh exists (lsp.lua gates on it)',
        optional = true,
        platforms = { linux = true, mac = true }, -- Windows already has one
        check = function() return sys.has('pwsh') or sys.has('powershell') end,
        packages = { brew = 'cask:powershell', apk = 'powershell' },
        note = 'See https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux',
    },
    {
        name = 'quarto',
        desc = 'Quarto CLI -- render/preview .qmd documents',
        optional = true,
        check = function() return sys.has('quarto') end,
        packages = { brew = 'cask:quarto', winget = 'Posit.Quarto' },
        fallback = function()
            return from_github('quarto-dev/quarto-cli', {
                ('linux%%-%s%%.tar%%.gz$'):format(sys.arch() == 'arm64' and 'arm64' or 'amd64'),
                'linux%-amd64%.tar%.gz$',
            }, function(dir)
                local target = vim.fs.joinpath(sys.home(), '.local', 'share', 'quarto')
                local src = find_file(dir, 'quarto')
                if not src then
                    return false
                end
                local root = vim.fs.dirname(vim.fs.dirname(src))
                sys.mkdirp(vim.fs.dirname(target))
                sys.stream({ 'rm', '-rf', target })
                if not sys.stream({ 'cp', '-r', root, target }) then
                    return false
                end
                sys.mkdirp(sys.local_bin())
                local link = vim.fs.joinpath(sys.local_bin(), 'quarto')
                pcall(vim.uv.fs_unlink, link)
                vim.uv.fs_symlink(vim.fs.joinpath(target, 'bin', 'quarto'), link)
                return true
            end)
        end,
        note = 'quarto.lua notes the CLI is not needed for LSP-in-cells or the cell runner',
    },
    {
        name = 'nerd-font',
        desc = 'glyphs for nvim-web-devicons and lualine',
        optional = true,
        check = function()
            if sys.is_windows or sys.is_mac then
                return false -- no cheap probe; only installed on request
            end
            local r = sys.capture({ 'fc-list' }, { timeout = 30000 })
            return r.code == 0 and r.stdout:lower():find('nerd') ~= nil
        end,
        packages = {
            pacman = 'ttf-jetbrains-mono-nerd',
            brew = 'cask:font-jetbrains-mono-nerd-font',
            apk = 'font-jetbrains-mono-nerd',
        },
        fallback = function()
            local dest = sys.is_windows
                and vim.fs.joinpath(os.getenv('LOCALAPPDATA') or sys.home(), 'Microsoft', 'Windows', 'Fonts')
                or vim.fs.joinpath(sys.home(), '.local', 'share', 'fonts')
            local ok = from_github('ryanoasis/nerd-fonts', { '^JetBrainsMono%.tar%.xz$', '^JetBrainsMono%.zip$' },
                function(dir)
                    sys.mkdirp(dest)
                    local copied = 0
                    for name, type_ in vim.fs.dir(dir, { depth = 2 }) do
                        if type_ == 'file' and name:match('%.ttf$') then
                            local src = vim.fs.joinpath(dir, name)
                            if vim.uv.fs_copyfile(src, vim.fs.joinpath(dest, vim.fs.basename(name))) then
                                copied = copied + 1
                            end
                        end
                    end
                    return copied > 0
                end)
            if ok and sys.has('fc-cache') then
                sys.stream({ 'fc-cache', '-f' })
            end
            if ok then
                log.info('Set your terminal font to "JetBrainsMono Nerd Font"')
            end
            return ok
        end,
    },
}

--- Lookup ------------------------------------------------------------------

M.by_name = {}
for _, node in ipairs(M.nodes) do
    M.by_name[node.name] = node
end

--- Add the repo-side steps (submodules, Mason, parsers...) to the tree.
--- @param steps table[]
function M.extend(steps)
    for _, node in ipairs(steps) do
        M.nodes[#M.nodes + 1] = node
        M.by_name[node.name] = node
    end
end

--- Does this node apply to the platform we are on?
--- @param node table
--- @return boolean
function M.applies(node)
    if not node.platforms then
        return true
    end
    if sys.is_windows then
        return node.platforms.windows == true
    end
    if sys.is_mac then
        return node.platforms.mac == true
    end
    return node.platforms.linux == true
end

--- Install a node using the first source that exists for this platform.
--- @param node table
--- @return boolean success
--- @return string reason
function M.install(node)
    if node.install then
        return node.install(), 'custom'
    end

    local manager = pm.id()
    local pkg = node.packages and node.packages[manager]
    if pkg then
        local list = type(pkg) == 'table' and pkg or { pkg }
        local all_ok = true
        for _, name in ipairs(list) do
            if pm.available(name) then
                if not pm.install(name) then
                    all_ok = false
                end
            else
                log.dim(('%s has no package named %q'):format(manager, name))
                all_ok = false
            end
        end
        if all_ok then
            -- Some package managers ship a version too old to be useful;
            -- re-run the node's own check before declaring victory.
            if not node.verify_packages or node.check() then
                return true, manager
            end
            log.warn('Package manager version is not good enough; trying the fallback')
        end
    end

    if node.fallback then
        return node.fallback(), 'fallback'
    end
    return false, 'none'
end

return M
