-- Installer for this Neovim configuration.
--
--   nvim -l install/install.lua [options]
--
-- Neovim is the one thing that has to exist first, so it is also the thing
-- that runs the installer: `nvim -l` is a plain Lua interpreter with vim.system,
-- vim.uv, vim.fs and vim.json attached, on every platform Neovim runs on.
-- install.sh and install.ps1 exist only to put Neovim (and git) in place and
-- then call this file.
--
-- The work is a dependency graph, not a script: lib/manifest.lua declares what
-- is needed and where each thing comes from, lib/steps.lua adds the steps that
-- act on the checkout itself, and this file orders and runs them.

-- ':p' matters: the script is usually invoked by a relative path, and every
-- path derived from it (the config root, the lib directory) has to be absolute
-- because the steps run commands from other working directories.
local script_path = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p'))
local install_dir = vim.fs.dirname(script_path)
package.path = table.concat({
    install_dir .. '/?.lua',
    install_dir .. '/?/init.lua',
    package.path,
}, ';')

local log = require('lib.log')
local manifest = require('lib.manifest')
local pm = require('lib.pm')
local steps = require('lib.steps')
local sys = require('lib.sys')

local CONFIG_ROOT = vim.fs.dirname(install_dir)

--- Options ------------------------------------------------------------------

local opts = {
    check = false,
    tree = false,
    dry_run = false,
    yes = false,
    all = false,
    with = {},
    skip = {},
    only = {},
}

local USAGE = [[
Install everything this Neovim config needs.

  nvim -l install/install.lua [options]

Options:
  --check         Report what is present and what is missing; change nothing
  --tree          Print the dependency tree and exit
  --dry-run       Say what would be installed without installing it
  -y, --yes       Do not ask for confirmation
  --all           Include every optional component
  --with=a,b      Include specific optional components (see --tree)
  --skip=a,b      Skip these components
  --only=a,b      Install only these (their requirements come along)
  --no-color      Plain output
  -h, --help      This text
]]

local function split_list(value)
    local out = {}
    for item in tostring(value):gmatch('[^,]+') do
        out[item:gsub('%s', '')] = true
    end
    return out
end

for _, argument in ipairs(_G.arg or {}) do
    local key, value = argument:match('^%-%-([%w%-]+)=(.*)$')
    if key == 'with' then
        opts.with = split_list(value)
    elseif key == 'skip' then
        opts.skip = split_list(value)
    elseif key == 'only' then
        opts.only = split_list(value)
    elseif argument == '--check' then
        opts.check = true
    elseif argument == '--tree' then
        opts.tree = true
    elseif argument == '--dry-run' then
        opts.dry_run = true
    elseif argument == '-y' or argument == '--yes' then
        opts.yes = true
    elseif argument == '--all' then
        opts.all = true
    elseif argument == '--no-color' then
        log.set_color(false)
    elseif argument == '-h' or argument == '--help' then
        io.write(USAGE)
        os.exit(0)
    else
        io.write('Unknown option: ' .. argument .. '\n\n' .. USAGE)
        os.exit(2)
    end
end

--- Graph -------------------------------------------------------------------

manifest.extend(steps.build(CONFIG_ROOT))

--- Depth-first topological sort. Requirements come out before dependents.
--- @return table[] ordered
local function topo_sort()
    local ordered, state = {}, {}

    local function visit(name, trail)
        local node = manifest.by_name[name]
        if not node then
            -- A requirement naming something that does not exist is a bug in
            -- the manifest, not a user error; say so loudly.
            log.err(('Unknown dependency %q (required by %s)'):format(name, trail))
            os.exit(1)
        end
        if state[name] == 'done' then
            return
        end
        if state[name] == 'visiting' then
            log.err(('Dependency cycle at %q (%s)'):format(name, trail))
            os.exit(1)
        end
        state[name] = 'visiting'
        for _, requirement in ipairs(node.requires or {}) do
            visit(requirement, trail .. ' -> ' .. name)
        end
        state[name] = 'done'
        ordered[#ordered + 1] = node
    end

    for _, node in ipairs(manifest.nodes) do
        visit(node.name, node.name)
    end
    return ordered
end

local ordered = topo_sort()

--- Which nodes are we actually doing? ---------------------------------------

--- Optional nodes are opt-in, except when something selected needs them.
local function wanted(node)
    if opts.all then
        return true
    end
    if not node.optional then
        return true
    end
    return opts.with[node.name] == true
end

-- --only=a,b means "a, b, and whatever they need"
local only_closure
if next(opts.only) then
    only_closure = {}
    local function pull(name)
        if only_closure[name] then
            return
        end
        only_closure[name] = true
        local node = manifest.by_name[name]
        for _, requirement in ipairs(node and node.requires or {}) do
            pull(requirement)
        end
    end
    for name in pairs(opts.only) do
        if not manifest.by_name[name] then
            log.err(('Unknown component %q'):format(name))
            os.exit(2)
        end
        pull(name)
    end
end

--- @return boolean selected, string? reason
local function selected(node)
    if not manifest.applies(node) then
        return false, 'not needed on this platform'
    end
    if opts.skip[node.name] then
        return false, 'skipped (--skip)'
    end
    if only_closure and not only_closure[node.name] then
        return false, 'not in --only'
    end
    if not wanted(node) then
        return false, 'optional; add --with=' .. node.name
    end
    return true
end

--- Reporting ----------------------------------------------------------------

local function print_tree()
    log.banner('Dependency tree')
    local printed = {}

    local function show(node, depth)
        local pad = string.rep('   ', depth)
        local mark = node.optional and log.paint('dim', ' (optional)') or ''
        local seen = printed[node.name] and log.paint('dim', ' ...') or ''
        log.plain(('%s%s%s%s'):format(pad, log.paint('bold', node.name), mark, seen))
        if not printed[node.name] then
            printed[node.name] = true
            if depth == 0 or true then
                log.plain(pad .. '   ' .. log.paint('dim', node.desc))
            end
            for _, requirement in ipairs(node.requires or {}) do
                show(manifest.by_name[requirement], depth + 1)
            end
        end
    end

    -- Roots are the nodes nothing else depends on: printing from there shows
    -- the whole graph top-down.
    local depended_on = {}
    for _, node in ipairs(manifest.nodes) do
        for _, requirement in ipairs(node.requires or {}) do
            depended_on[requirement] = true
        end
    end
    for _, node in ipairs(manifest.nodes) do
        if not depended_on[node.name] then
            show(node, 0)
        end
    end
    log.plain('')
    log.dim('Indented entries are requirements of the entry above them.')
end

local function describe_platform()
    local name = sys.is_windows and 'Windows' or (sys.is_mac and 'macOS' or ('Linux (' .. sys.linux_id() .. ')'))
    log.info(('Platform      %s %s'):format(name, sys.arch()))
    log.info(('Package mgr   %s'):format(pm.id()))
    local v = vim.version()
    log.info(('Neovim        %d.%d.%d'):format(v.major, v.minor, v.patch))
    log.info(('Config        %s'):format(CONFIG_ROOT))
end

--- Run ----------------------------------------------------------------------

log.banner('Neovim config installer')
describe_platform()

if opts.tree then
    print_tree()
    os.exit(0)
end

-- ~/.local/bin is where hand-installed tools land; make sure this process can
-- see them the moment they appear, whatever the login shell has done.
sys.prepend_path(sys.local_bin())
sys.prepend_path(vim.fs.joinpath(sys.home(), '.cargo', 'bin'))

log.banner('Checking what is already here')

local plan = {}
for _, node in ipairs(ordered) do
    local take, reason = selected(node)
    local ok, present = pcall(node.check)
    present = ok and present or false
    if not take then
        -- Report every applicable node, including optional ones that happen
        -- to be present: "nothing printed" reads as "not considered".
        if present then
            log.skip(('%-20s present (optional)'):format(node.name))
        else
            log.skip(('%-20s %s'):format(node.name, reason))
        end
    elseif present and not node.always then
        log.ok(('%-20s present'):format(node.name))
    else
        log.warn(('%-20s %s'):format(node.name, node.always and 'will run' or 'missing'))
        plan[#plan + 1] = node
    end
end

if #plan == 0 then
    log.banner('Nothing to do')
    log.ok('Everything this config needs is already installed.')
    os.exit(0)
end

if opts.check then
    log.banner('Summary')
    local missing, rerun = {}, {}
    for _, node in ipairs(plan) do
        table.insert(node.always and rerun or missing, node)
    end
    if #missing > 0 then
        log.info(('%d component(s) missing:'):format(#missing))
        for _, node in ipairs(missing) do
            log.info('  ' .. node.name .. ' -- ' .. node.desc)
        end
    else
        log.ok('Nothing is missing.')
    end
    if #rerun > 0 then
        log.info('Steps that re-run every time (cheap when there is nothing to do):')
        for _, node in ipairs(rerun) do
            log.dim('  ' .. node.name)
        end
    end
    if #missing > 0 then
        log.dim('Run without --check to install them.')
    end
    -- Non-zero when something *required* is genuinely absent, so --check works
    -- as a health gate. `always` steps are in the plan by definition -- they
    -- re-run every time -- and must not make a healthy machine look broken.
    for _, node in ipairs(plan) do
        if not node.optional and not node.always then
            os.exit(1)
        end
    end
    os.exit(0)
end

log.banner('Plan')
for index, node in ipairs(plan) do
    log.plain(('  %d. %s %s'):format(index, log.paint('bold', node.name), log.paint('dim', '-- ' .. node.desc)))
end

if opts.dry_run then
    log.plain('')
    log.dim('Dry run: nothing was installed.')
    os.exit(0)
end

if not opts.yes then
    log.plain('')
    if not log.confirm(('Install these %d component(s)?'):format(#plan), true) then
        log.info('Nothing done.')
        os.exit(0)
    end
end

log.banner('Installing')

local results = {}
for index, node in ipairs(plan) do
    log.step(('[%d/%d] %s'):format(index, #plan, node.name))
    log.dim(node.desc)

    local ok, success, via = pcall(manifest.install, node)
    if not ok then
        log.err(tostring(success))
        success = false
    end

    if success and node.post then
        pcall(node.post)
    end

    -- Trust the node's own check over the installer's exit code: a package
    -- manager can succeed while leaving nothing useful on PATH. Two kinds of
    -- node are exempt -- ones that run every time, and ones whose work is
    -- legitimately finished elsewhere (blink fetches its matcher on first
    -- start), where the step's own verdict is the only meaningful one.
    local verified
    if node.always or node.trust_install then
        verified = success == true
    else
        verified = select(2, pcall(node.check)) == true
    end

    if verified then
        log.ok(node.name .. ' installed' .. (via and via ~= 'custom' and (' (' .. via .. ')') or ''))
        results[node.name] = 'installed'
    elseif node.optional then
        log.warn(node.name .. ' could not be installed')
        if node.note then
            log.dim(node.note)
        end
        results[node.name] = 'skipped'
    else
        log.err(node.name .. ' failed')
        if node.note then
            log.dim(node.note)
        end
        results[node.name] = 'failed'
    end
end

--- Report -------------------------------------------------------------------

log.banner('Result')

local failed, skipped = {}, {}
for name, outcome in pairs(results) do
    if outcome == 'failed' then
        failed[#failed + 1] = name
    elseif outcome == 'skipped' then
        skipped[#skipped + 1] = name
    end
end
table.sort(failed)
table.sort(skipped)

for _, node in ipairs(plan) do
    local outcome = results[node.name]
    if outcome == 'installed' then
        log.ok(node.name)
    elseif outcome == 'skipped' then
        log.warn(node.name .. ' (optional, not installed)')
    else
        log.err(node.name)
    end
end

if not sys.on_path(sys.local_bin()) and not sys.is_windows then
    log.plain('')
    log.warn('~/.local/bin is not on your PATH')
    log.dim('Neovim adds it itself (init.lua), but your shell will not see')
    log.dim('jupytext or verible until you add:')
    log.dim('  export PATH="$HOME/.local/bin:$PATH"')
end

log.plain('')
if #failed > 0 then
    log.err(('%d required component(s) failed: %s'):format(#failed, table.concat(failed, ', ')))
    log.dim('Re-run the installer to retry; it only touches what is still missing.')
    os.exit(1)
end

log.ok('Done. Start nvim -- Mason and treesitter have nothing left to fetch.')
if #skipped > 0 then
    log.dim('Optional and not installed: ' .. table.concat(skipped, ', '))
end
os.exit(0)
