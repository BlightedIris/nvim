-- Process execution, platform detection, and downloads.
--
-- Two ways to run a command, and the difference matters:
--   capture() -- vim.system, output collected, no terminal. For probes.
--   stream()  -- os.execute, output goes straight to the terminal and stdin
--               is inherited. For installs, which print progress and may ask
--               for a sudo password or a winget agreement.
local log = require('lib.log')

local M = {}

--- Platform -----------------------------------------------------------------

M.is_windows = vim.fn.has('win32') == 1
M.is_mac = vim.fn.has('mac') == 1
M.is_linux = not M.is_windows and not M.is_mac

-- uname -m normalised to the names release assets actually use.
function M.arch()
    if M.cached_arch then
        return M.cached_arch
    end
    local raw
    if M.is_windows then
        raw = os.getenv('PROCESSOR_ARCHITECTURE') or 'AMD64'
    else
        local r = M.capture({ 'uname', '-m' })
        raw = (r.stdout or ''):gsub('%s+$', '')
    end
    raw = raw:lower()
    local map = {
        x86_64 = 'x86_64', amd64 = 'x86_64',
        aarch64 = 'arm64', arm64 = 'arm64',
    }
    M.cached_arch = map[raw] or raw
    return M.cached_arch
end

-- The /etc/os-release ID, e.g. "arch", "ubuntu", "fedora". Empty elsewhere.
function M.linux_id()
    if not M.is_linux then
        return ''
    end
    local f = io.open('/etc/os-release', 'r')
    if not f then
        return ''
    end
    local content = f:read('a')
    f:close()
    return (content:match('\nID=([%w%-%._]+)') or content:match('^ID=([%w%-%._]+)') or '')
        :gsub('"', '')
end

--- Paths --------------------------------------------------------------------

function M.home()
    return vim.fn.expand('~')
end

-- Where hand-installed binaries land. init.lua prepends this to PATH, so
-- anything dropped here is visible to :terminal and to executable() gates.
function M.local_bin()
    return vim.fs.joinpath(M.home(), '.local', 'bin')
end

function M.exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

function M.mkdirp(path)
    vim.fn.mkdir(path, 'p')
end

--- Command execution --------------------------------------------------------

--- Quote one argument for the platform shell.
local function quote(arg)
    if M.is_windows then
        -- cmd.exe: double quotes, and a literal " has to be backslash-escaped
        if arg:match('^[%w%-%._\\/:=]+$') then
            return arg
        end
        return '"' .. arg:gsub('"', '\\"') .. '"'
    end
    if arg:match("^[%w%-%._/:=,@+]+$") then
        return arg
    end
    return "'" .. arg:gsub("'", "'\\''") .. "'"
end

--- @param argv string[]
--- @return string
function M.shell_join(argv)
    local parts = {}
    for _, arg in ipairs(argv) do
        parts[#parts + 1] = quote(arg)
    end
    return table.concat(parts, ' ')
end

--- Run quietly and collect the output.
--- @param argv string[]
--- @param opts? { cwd?: string, timeout?: number, env?: table<string,string> }
--- @return { code: integer, stdout: string, stderr: string }
function M.capture(argv, opts)
    opts = opts or {}
    local ok, result = pcall(function()
        return vim
            .system(argv, {
                text = true,
                cwd = opts.cwd,
                timeout = opts.timeout,
                env = opts.env,
            })
            :wait()
    end)
    if not ok then
        -- vim.system throws when argv[1] does not exist at all
        return { code = 127, stdout = '', stderr = tostring(result) }
    end
    return { code = result.code, stdout = result.stdout or '', stderr = result.stderr or '' }
end

--- Run with the terminal attached: output streams live, stdin is inherited so
--- password and confirmation prompts work.
--- @param argv string[]
--- @param opts? { cwd?: string }
--- @return boolean success
--- @return integer code
function M.stream(argv, opts)
    opts = opts or {}
    local cmd = M.shell_join(argv)
    if opts.cwd then
        -- `cd` in a subshell keeps the installer's own cwd untouched
        if M.is_windows then
            cmd = 'cd /d ' .. quote(opts.cwd) .. ' && ' .. cmd
        else
            cmd = 'cd ' .. quote(opts.cwd) .. ' && ' .. cmd
        end
    end
    io.stdout:flush()
    local ok, _, code = os.execute(cmd)
    -- Lua 5.1 returns the raw exit status as the first value; 5.2+ returns a
    -- boolean plus the code. LuaJIT (what nvim ships) is the 5.1 shape.
    if type(ok) == 'number' then
        code = ok
        ok = code == 0
    end
    code = code or (ok and 0 or 1)
    -- Lua 5.1's os.execute hands back C system()'s wait status, so exit 1
    -- arrives as 256. Normalise it so the number means what callers expect.
    if not M.is_windows and code > 255 then
        code = math.floor(code / 256)
    end
    return ok == true, code
end

--- Is this executable on PATH?
--- @param name string
--- @return boolean
function M.has(name)
    return vim.fn.executable(name) == 1
end

--- Full path of an executable, or nil.
function M.which(name)
    local path = vim.fn.exepath(name)
    if path == nil or path == '' then
        return nil
    end
    return path
end

--- Privilege escalation -----------------------------------------------------

M.sudo_primed = false

--- Prefix a command with sudo when the system package manager needs root.
--- Priming once up front means the password prompt happens at a predictable
--- moment instead of in the middle of a download.
--- @param argv string[]
--- @return string[]
function M.with_sudo(argv)
    if M.is_windows or vim.uv.getuid() == 0 then
        return argv
    end
    if not M.has('sudo') then
        log.warn('sudo not found; running the command unprivileged')
        return argv
    end
    if not M.sudo_primed then
        log.info('Requesting sudo (needed for system package installs)')
        M.stream({ 'sudo', '-v' })
        M.sudo_primed = true
    end
    local out = { 'sudo' }
    for _, arg in ipairs(argv) do
        out[#out + 1] = arg
    end
    return out
end

--- Downloads ----------------------------------------------------------------

--- @param url string
--- @param dest string
--- @return boolean
function M.download(url, dest)
    M.mkdirp(vim.fs.dirname(dest))
    if M.has('curl') then
        local ok = M.stream({ 'curl', '-fL', '--progress-bar', '-o', dest, url })
        return ok
    end
    if M.has('wget') then
        return M.stream({ 'wget', '-q', '--show-progress', '-O', dest, url })
    end
    if M.is_windows then
        return M.stream({
            'powershell', '-NoProfile', '-Command',
            ("Invoke-WebRequest -Uri '%s' -OutFile '%s'"):format(url, dest),
        })
    end
    log.err('No downloader available (need curl or wget)')
    return false
end

--- Fetch a URL into a string. Used for the GitHub release API.
--- @param url string
--- @return string?
function M.fetch(url)
    if M.has('curl') then
        local r = M.capture({ 'curl', '-fsSL', url }, { timeout = 60000 })
        if r.code == 0 then
            return r.stdout
        end
        return nil
    end
    if M.is_windows then
        local r = M.capture({
            'powershell', '-NoProfile', '-Command',
            ("(Invoke-WebRequest -UseBasicParsing -Uri '%s').Content"):format(url),
        }, { timeout = 60000 })
        if r.code == 0 then
            return r.stdout
        end
    end
    return nil
end

--- Unpack .tar.gz / .tar.xz / .zip into `dest`.
--- @param archive string
--- @param dest string
--- @return boolean
function M.extract(archive, dest)
    M.mkdirp(dest)
    if archive:match('%.zip$') then
        if M.has('unzip') then
            return M.stream({ 'unzip', '-q', '-o', archive, '-d', dest })
        end
        if M.is_windows then
            return M.stream({
                'powershell', '-NoProfile', '-Command',
                ("Expand-Archive -Force -Path '%s' -DestinationPath '%s'"):format(archive, dest),
            })
        end
        -- bsdtar (and GNU tar 1.32+) reads zips too
        return M.stream({ 'tar', '-xf', archive, '-C', dest })
    end
    return M.stream({ 'tar', '-xf', archive, '-C', dest })
end

--- Version helpers ----------------------------------------------------------

--- First "x.y.z" looking thing in a command's output.
--- @param argv string[]
--- @return string?
function M.version_of(argv)
    local r = M.capture(argv, { timeout = 20000 })
    if r.code ~= 0 then
        return nil
    end
    return (r.stdout .. r.stderr):match('(%d+%.%d+%.?%d*)')
end

--- Compare dotted versions. Returns true when `have` >= `want`.
--- @param have string?
--- @param want string
--- @return boolean
function M.version_at_least(have, want)
    if not have then
        return false
    end
    local function parts(v)
        local out = {}
        for n in tostring(v):gmatch('%d+') do
            out[#out + 1] = tonumber(n)
        end
        return out
    end
    local a, b = parts(have), parts(want)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then
            return x > y
        end
    end
    return true
end

--- GitHub releases ----------------------------------------------------------

--- Pick a release asset by pattern from a repo's latest release.
--- @param repo string  "owner/name"
--- @param patterns string[]  lua patterns, tried in order
--- @return { url: string, name: string, tag: string }?
function M.github_asset(repo, patterns)
    local body = M.fetch(('https://api.github.com/repos/%s/releases/latest'):format(repo))
    if not body then
        return nil
    end
    local ok, data = pcall(vim.json.decode, body)
    if not ok or type(data) ~= 'table' or not data.assets then
        return nil
    end
    for _, pattern in ipairs(patterns) do
        for _, asset in ipairs(data.assets) do
            if asset.name:match(pattern) then
                return { url = asset.browser_download_url, name = asset.name, tag = data.tag_name }
            end
        end
    end
    return nil
end

--- Temp space ---------------------------------------------------------------

function M.tempdir(name)
    local base = vim.fn.tempname()
    local dir = vim.fs.joinpath(base, name or 'work')
    M.mkdirp(dir)
    return dir
end

--- PATH ---------------------------------------------------------------------

--- Is `dir` on the PATH of this process?
function M.on_path(dir)
    local sep = M.is_windows and ';' or ':'
    local target = vim.fs.normalize(dir):lower()
    for entry in (os.getenv('PATH') or ''):gmatch('[^' .. sep .. ']+') do
        if vim.fs.normalize(entry):lower() == target then
            return true
        end
    end
    return false
end

--- Make `dir` visible to the rest of this run, whatever the shell does later.
function M.prepend_path(dir)
    local sep = M.is_windows and ';' or ':'
    if not M.on_path(dir) then
        vim.env.PATH = dir .. sep .. vim.env.PATH
    end
end

return M
