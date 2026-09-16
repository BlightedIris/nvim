-- The steps that act on the config itself, rather than on the system.
--
-- These are manifest nodes like any other (same check/install contract), so
-- they take part in the same dependency ordering -- Mason cannot run before
-- the submodules exist, parsers cannot build before tree-sitter-cli is there.
--
-- Anything needing the real config loaded runs a nested `nvim --headless`.
-- Two details make those runs safe:
--   * a dummy file argument, so argc > 0. lua/plugins/mini-sessions.lua
--     treats an argument as "quick edit" and skips both restoring a session
--     on entry and *writing* one on exit -- without it, every headless run
--     would clobber a saved session.
--   * an explicit rtp/packpath prepend, so a clone that does not live at
--     ~/.config/nvim still loads its own plugins.
local log = require('lib.log')
local sys = require('lib.sys')

local M = {}

local root -- config root, set by M.setup

--- Headless helpers ---------------------------------------------------------

local dummy_arg

local function dummy_file()
    if not dummy_arg then
        dummy_arg = vim.fs.joinpath(sys.tempdir('headless'), 'installer.txt')
        local f = io.open(dummy_arg, 'w')
        if f then
            f:write('')
            f:close()
        end
    end
    return dummy_arg
end

--- Run Neovim headlessly with this config loaded.
--- @param commands string[] `-c` commands, run in order before quitting
--- @return boolean
local function headless(commands)
    local escaped = vim.fn.fnameescape(root)
    local argv = {
        vim.v.progpath,
        '--headless',
        '--cmd', ('set runtimepath^=%s packpath^=%s'):format(escaped, escaped),
        '-u', vim.fs.joinpath(root, 'init.lua'),
    }
    for _, cmd in ipairs(commands) do
        argv[#argv + 1] = '-c'
        argv[#argv + 1] = cmd
    end
    argv[#argv + 1] = '-c'
    argv[#argv + 1] = 'qa!'
    argv[#argv + 1] = dummy_file()
    return (sys.stream(argv, { cwd = root }))
end

--- Run a Lua script in a bare Neovim (`-l` does not source the user config).
--- Used where loading the whole config would start work we want to control
--- ourselves, e.g. the parser install.
--- @param script string  lua source
--- @param args string[]
--- @return boolean
local function headless_lua(script, args)
    local path = vim.fs.joinpath(sys.tempdir('script'), 'step.lua')
    local f = io.open(path, 'w')
    if not f then
        return false
    end
    f:write(script)
    f:close()

    local argv = { vim.v.progpath, '--clean', '-l', path }
    for _, arg in ipairs(args or {}) do
        argv[#argv + 1] = arg
    end
    return (sys.stream(argv, { cwd = root }))
end

--- Read a quoted string list out of a config file, e.g.
---   local ensure_tools = { "shellcheck", "shfmt" }
--- Keeps the installer in step with the config instead of duplicating the
--- list here; returns nil when the shape has changed.
--- @param file string
--- @param key string
--- @return string[]?
local function read_string_list(file, key)
    local f = io.open(vim.fs.joinpath(root, file), 'r')
    if not f then
        return nil
    end
    local content = f:read('a')
    f:close()
    local body = content:match(key .. '%s*=%s*{(.-)}')
    if not body then
        return nil
    end
    local out = {}
    for item in body:gmatch('["\']([%w%-%._]+)["\']') do
        out[#out + 1] = item
    end
    return #out > 0 and out or nil
end

--- Steps --------------------------------------------------------------------

--- @param config_root string
--- @return table[]
function M.build(config_root)
    root = config_root

    local pack_dir = vim.fs.joinpath(root, 'pack', 'basics', 'start')
    -- init.lua points g:python3_host_prog at <data>/venv; matching that exactly
    -- is what makes molten's remote plugin work.
    local venv = vim.fs.joinpath(vim.fn.stdpath('data'), 'venv')
    local venv_python = sys.is_windows and vim.fs.joinpath(venv, 'Scripts', 'python.exe')
        or vim.fs.joinpath(venv, 'bin', 'python')

    return {
        {
            name = 'submodules',
            desc = 'checks out the plugins under pack/*/start (they are git submodules)',
            requires = { 'git' },
            check = function()
                -- plenary is required by init.lua's very first line, so its
                -- absence means the submodules were never fetched
                return sys.exists(vim.fs.joinpath(pack_dir, 'plenary-nvim', 'lua'))
            end,
            install = function()
                return (sys.stream({ 'git', 'submodule', 'update', '--init', '--recursive' }, { cwd = root }))
            end,
        },

        {
            name = 'nvim-venv',
            desc = 'the Python interpreter molten runs in (pynvim, jupyter_client, ...)',
            requires = { 'python', 'uv' },
            check = function()
                if not sys.exists(venv_python) then
                    return false
                end
                local r = sys.capture({ venv_python, '-c', 'import pynvim, jupyter_client' })
                return r.code == 0
            end,
            install = function()
                -- The list init.lua documents. Split in two: the first group
                -- is what molten cannot start without, the second is optional
                -- output formats whose wheels sometimes need system libraries
                -- (cairo, in cairosvg's case) and may legitimately fail.
                local core = { 'pynvim', 'jupyter_client', 'ipykernel' }
                local extra = {
                    'nbformat', 'pillow', 'pyperclip', 'requests',
                    'websocket-client', 'cairosvg', 'pnglatex',
                }

                local use_uv = sys.has('uv')
                if not sys.exists(venv_python) then
                    log.info('Creating ' .. venv)
                    local created
                    if use_uv then
                        created = sys.stream({ 'uv', 'venv', venv })
                    else
                        local py = sys.is_windows and 'python' or 'python3'
                        created = sys.stream({ py, '-m', 'venv', venv })
                    end
                    if not created then
                        return false
                    end
                end

                local function pip_install(packages, label)
                    local argv
                    if use_uv then
                        argv = { 'uv', 'pip', 'install', '--python', venv_python }
                    else
                        argv = { venv_python, '-m', 'pip', 'install' }
                    end
                    for _, pkg in ipairs(packages) do
                        argv[#argv + 1] = pkg
                    end
                    local ok = sys.stream(argv)
                    if not ok then
                        log.warn(label .. ' packages failed to install')
                    end
                    return ok
                end

                if not pip_install(core, 'Core') then
                    return false
                end
                -- Best effort: a missing cairo shouldn't fail the install
                pip_install(extra, 'Optional')

                if sys.is_windows then
                    log.warn('init.lua hardcodes ~/.local/share/nvim/venv/bin/python for '
                        .. 'g:python3_host_prog, which is a POSIX path')
                    log.info('On Windows, point it at ' .. venv_python)
                end
                return true
            end,
        },

        {
            name = 'blink-fuzzy',
            desc = 'builds blink.cmp\'s Rust fuzzy matcher (otherwise it downloads a prebuilt one)',
            -- Not optional: lua/plugins/blink.lua forces
            -- `fuzzy.implementation = 'rust'`, so without the library blink
            -- errors on setup until it has fetched one.
            requires = { 'rust', 'submodules' },
            -- Without cargo the step's job is to explain, not to build, so
            -- its own return value decides the outcome rather than check().
            trust_install = true,
            check = function()
                local dir = vim.fs.joinpath(pack_dir, 'blink-cmp')
                local release = vim.fs.joinpath(dir, 'target', 'release')
                local extension = sys.is_windows and '.dll' or (sys.is_mac and '.dylib' or '.so')
                if not sys.exists(vim.fs.joinpath(release, 'libblink_cmp_fuzzy' .. extension)) then
                    return false
                end
                local f = io.open(vim.fs.joinpath(release, 'version'), 'r')
                if not f then
                    return false
                end
                local built = (f:read('l') or ''):gsub('%s', '')
                f:close()
                if built == '' then
                    return false
                end
                -- 40 characters is a SHA, i.e. a local build, and it has to
                -- match the checked-out commit. Anything else is a tag, which
                -- means blink downloaded a prebuilt binary -- equally fine.
                if #built ~= 40 then
                    return true
                end
                local head = sys.capture({ 'git', 'rev-parse', 'HEAD' }, { cwd = dir })
                return built == (head.stdout or ''):gsub('%s', '')
            end,
            install = function()
                local dir = vim.fs.joinpath(pack_dir, 'blink-cmp')
                if not sys.has('cargo') then
                    -- blink fetches a prebuilt binary on its first real
                    -- startup, so this self-heals; say so rather than failing
                    -- a step nobody can act on without installing Rust.
                    log.warn('cargo not available -- blink.cmp will download a prebuilt')
                    log.dim('matcher the first time you start nvim. Add --with=rust to build it here.')
                    return true
                end
                log.info('cargo build --release (blink.cmp pins the nightly toolchain)')
                if not sys.stream({ 'cargo', 'build', '--release' }, { cwd = dir }) then
                    log.warn('Build failed; blink.cmp falls back to a prebuilt download at runtime')
                    return true
                end
                -- blink compares this file against the checked-out SHA to
                -- decide whether the local build is current; without it the
                -- build is ignored.
                local head = sys.capture({ 'git', 'rev-parse', 'HEAD' }, { cwd = dir })
                local sha = (head.stdout or ''):gsub('%s', '')
                if sha == '' then
                    return false
                end
                local f = io.open(vim.fs.joinpath(dir, 'target', 'release', 'version'), 'w')
                if not f then
                    return false
                end
                f:write(sha)
                f:close()
                return true
            end,
        },

        {
            name = 'treesitter-parsers',
            desc = 'compiles every parser listed in lua/plugins/treesitter.lua',
            requires = { 'submodules', 'tree-sitter-cli', 'cc', 'curl' },
            check = function()
                -- Cheap probe: the parser directory holds one .so per
                -- language, so an empty/missing dir means nothing is built.
                -- The step itself is idempotent, so a partial set is fine to
                -- re-run.
                local dir = vim.fs.joinpath(vim.fn.stdpath('data'), 'site', 'parser')
                local handle = vim.uv.fs_scandir(dir)
                if not handle then
                    return false
                end
                local count = 0
                while vim.uv.fs_scandir_next(handle) do
                    count = count + 1
                end
                -- treesitter.lua asks for ~48 languages; anything far below
                -- that is an interrupted install worth finishing.
                return count >= 40
            end,
            install = function()
                -- Deliberately NOT the full config: loading it starts its own
                -- async install of the same parsers, and the two would race.
                -- Instead put just nvim-treesitter on the runtimepath and
                -- borrow the language list from the config by stubbing the
                -- module its setup file calls.
                local script = [[
local root = _G.arg[1]
vim.opt.runtimepath:prepend(root .. '/pack/basics/start/tree-sitter')

local wanted
package.loaded['nvim-treesitter'] = {
  install = function(langs) wanted = langs; return { wait = function() end } end,
}
local ok, err = pcall(dofile, root .. '/lua/plugins/treesitter.lua')
package.loaded['nvim-treesitter'] = nil
if not ok then
  io.write('could not read the language list: ' .. tostring(err) .. '\n')
  os.exit(1)
end
if type(wanted) ~= 'table' or #wanted == 0 then
  io.write('no languages found in lua/plugins/treesitter.lua\n')
  os.exit(1)
end

io.write(('Installing %d treesitter parsers (this takes a while)\n'):format(#wanted))
local installed, failed = pcall(function()
  require('nvim-treesitter').install(wanted, { summary = true }):wait(45 * 60 * 1000)
end)
if not installed then
  io.write('parser install failed: ' .. tostring(failed) .. '\n')
  os.exit(1)
end
]]
                return headless_lua(script, { root })
            end,
        },

        {
            name = 'mason-packages',
            desc = 'installs the LSP servers, debug adapters and tools the config ensures',
            -- blink-fuzzy is an ordering edge, not a functional one: this step
            -- loads the whole config headlessly, and a blink without its
            -- matcher fills that run with setup errors.
            requires = { 'submodules', 'blink-fuzzy', 'node', 'python', 'curl', 'archive-tools' },
            check = function()
                -- Handled inside the step: Mason knows what is installed far
                -- better than a file probe does, and MasonInstall is a no-op
                -- for packages that are already present.
                return false
            end,
            always = true, -- cheap when everything is already installed
            install = function()
                local tools = read_string_list('lua/plugins/mason.lua', 'ensure_tools') or {}
                local extra = table.concat(vim.tbl_map(function(t)
                    return ('%q'):format(t)
                end, tools), ', ')

                -- Resolve the wanted packages from the plugins themselves:
                -- mason-lspconfig and mason-nvim-dap both keep the
                -- ensure_installed list they were configured with, and both
                -- ship the name mapping (lspconfig/dap names are not Mason
                -- package names -- bashls is bash-language-server).
                local lua = ([[
local names = {}
local seen = {}
local function add(name) if name and not seen[name] then seen[name] = true; names[#names+1] = name end end

local ok_lsp, lsp = pcall(require, 'mason-lspconfig.settings')
if ok_lsp then
  local mappings = require('mason-lspconfig').get_mappings().lspconfig_to_package
  for _, server in ipairs(lsp.current.ensure_installed or {}) do
    add(mappings[server] or server)
  end
end

local ok_dap, dap = pcall(require, 'mason-nvim-dap.settings')
if ok_dap then
  local mappings = require('mason-nvim-dap.mappings.source').nvim_dap_to_package
  for _, adapter in ipairs(dap.current.ensure_installed or {}) do
    add(mappings[adapter] or adapter)
  end
end

for _, tool in ipairs({ %s }) do add(tool) end

local registry = require('mason-registry')
local missing = {}
for _, name in ipairs(names) do
  local ok, pkg = pcall(registry.get_package, name)
  if not ok or not pkg:is_installed() then missing[#missing+1] = name end
end
if #missing == 0 then
  print('All Mason packages are already installed: ' .. table.concat(names, ', '))
else
  print('Installing via Mason: ' .. table.concat(missing, ', '))
  vim.cmd('MasonInstall ' .. table.concat(missing, ' '))
end
]]):format(extra)

                return headless({ 'lua ' .. lua:gsub('\n', ' ') })
            end,
        },

        {
            name = 'remote-plugins',
            desc = 'registers molten\'s :Molten* commands (:UpdateRemotePlugins)',
            requires = { 'submodules', 'nvim-venv' },
            check = function()
                -- The manifest is rewritten whenever a remote plugin changes,
                -- so re-running is the only way to be sure it matches; the
                -- command is fast and idempotent.
                return false
            end,
            always = true,
            install = function()
                if not sys.exists(venv_python) then
                    log.warn('No Neovim venv; skipping (molten needs pynvim in g:python3_host_prog)')
                    return true
                end
                if not headless({ 'UpdateRemotePlugins' }) then
                    return false
                end

                -- A failed python host does not stop :UpdateRemotePlugins --
                -- it writes an *empty* manifest instead, silently removing
                -- every :Molten command. Check that molten actually made it in.
                local manifest_path = vim.fs.joinpath(vim.fn.stdpath('data'), 'rplugin.vim')
                local f = io.open(manifest_path, 'r')
                local content = f and f:read('a') or ''
                if f then
                    f:close()
                end
                if content:find('molten', 1, true) then
                    log.dim('molten registered in ' .. manifest_path)
                    return true
                end

                log.err('The manifest was written without molten -- its python3 host did not load')
                log.dim('Check that init.lua points g:python3_host_prog at ' .. venv_python)
                return false
            end,
        },
    }
end

return M
