-- The system package manager, behind one interface.
--
-- Every dependency in the manifest names its package per manager (see
-- lib/manifest.lua). This module is only about *how* to invoke the manager
-- that happens to be present -- it knows nothing about what is being
-- installed.
local log = require('lib.log')
local sys = require('lib.sys')

local M = {}

-- Ordered by specificity: on a Mac with Homebrew we want brew, not whatever
-- else may be lying around; on Windows, winget ships with the OS.
local managers = {
    {
        id = 'winget',
        probe = 'winget',
        args = function(pkg)
            return {
                'winget', 'install', '--id', pkg, '-e', '--source', 'winget',
                '--accept-source-agreements', '--accept-package-agreements',
                '--disable-interactivity',
            }
        end,
        sudo = false,
    },
    {
        id = 'brew',
        probe = 'brew',
        args = function(pkg)
            -- "cask:name" marks a GUI/font package
            local cask = pkg:match('^cask:(.+)$')
            if cask then
                return { 'brew', 'install', '--cask', cask }
            end
            return { 'brew', 'install', pkg }
        end,
        sudo = false,
    },
    {
        id = 'pacman',
        probe = 'pacman',
        args = function(pkg)
            return { 'pacman', '-S', '--needed', '--noconfirm', pkg }
        end,
        sudo = true,
    },
    {
        id = 'apt',
        probe = 'apt-get',
        args = function(pkg)
            return { 'apt-get', 'install', '-y', pkg }
        end,
        refresh = { 'apt-get', 'update' },
        sudo = true,
    },
    {
        id = 'dnf',
        probe = 'dnf',
        args = function(pkg)
            return { 'dnf', 'install', '-y', pkg }
        end,
        sudo = true,
    },
    {
        id = 'zypper',
        probe = 'zypper',
        args = function(pkg)
            return { 'zypper', '--non-interactive', 'install', pkg }
        end,
        sudo = true,
    },
    {
        id = 'apk',
        probe = 'apk',
        args = function(pkg)
            return { 'apk', 'add', pkg }
        end,
        sudo = true,
    },
}

local detected
local refreshed = false

--- @return table? manager
function M.detect()
    if detected ~= nil then
        return detected or nil
    end
    for _, manager in ipairs(managers) do
        if sys.has(manager.probe) then
            detected = manager
            return manager
        end
    end
    detected = false
    return nil
end

--- @return string
function M.id()
    local manager = M.detect()
    return manager and manager.id or 'none'
end

--- Install one package by its manager-specific name.
--- @param pkg string
--- @return boolean
function M.install(pkg)
    local manager = M.detect()
    if not manager then
        log.err('No supported package manager found')
        return false
    end

    if manager.refresh and not refreshed then
        refreshed = true
        sys.stream(manager.sudo and sys.with_sudo(manager.refresh) or manager.refresh)
    end

    local argv = manager.args(pkg)
    if manager.sudo then
        argv = sys.with_sudo(argv)
    end
    local ok = sys.stream(argv)
    return ok
end

--- Does this manager know the package? Cheap guard so a missing package name
--- reports as "not packaged here" instead of a wall of manager errors.
--- @param pkg string
--- @return boolean
function M.available(pkg)
    local manager = M.detect()
    if not manager then
        return false
    end
    local probes = {
        pacman = { 'pacman', '-Si', pkg },
        apt = { 'apt-cache', 'show', pkg },
        dnf = { 'dnf', 'info', pkg },
        zypper = { 'zypper', 'info', pkg },
        apk = { 'apk', 'info', pkg },
        brew = { 'brew', 'info', pkg:gsub('^cask:', '') },
    }
    local probe = probes[manager.id]
    if not probe then
        -- winget: querying is slow and noisy, just try the install
        return true
    end
    return sys.capture(probe, { timeout = 60000 }).code == 0
end

return M
