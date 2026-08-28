-- Session management. Git repos carry their own session file at the repo
-- root; everything else lives under stdpath('data')/sessions, which is
-- created on demand so the first write doesn't fail.
local sessions_dir = vim.fn.stdpath('data') .. '/sessions'
vim.fn.mkdir(sessions_dir, 'p')

-- mini.sessions wraps :mksession/:source, so 'sessionoptions' still governs
-- what actually gets captured. Drop the two that don't survive a restart well.
vim.opt.sessionoptions:remove('terminal') -- re-running shells lands in odd cwds
vim.opt.sessionoptions:remove('blank')    -- empty unnamed buffers aren't state

local sessions = require('mini.sessions')

-- neo-tree windows serialize into something :source can't rebuild.
local function close_sidebars()
    pcall(vim.cmd, 'Neotree close')
end

sessions.setup({
    -- Boot loading and exit saving are handled by the autocmds below (which
    -- also know about repo-local sessions), so mini.sessions itself must
    -- never touch sessions on its own.
    autoread = false,
    autowrite = false,
    directory = sessions_dir,
    hooks = {
        pre = { write = close_sidebars },
    },
})

-- Repo-local sessions -------------------------------------------------------

local repo_session_name = 'Session.vim'

local function git_root()
    local git_entry = vim.fs.find('.git', { path = vim.fn.getcwd(), upward = true })[1]
    return git_entry and vim.fs.dirname(git_entry) or nil
end

local function repo_session_file(root)
    return root .. '/' .. repo_session_name
end

-- The session file is machine state, not project content: keep it out of the
-- repo by appending one line to .gitignore (creating it if needed).
local function ensure_gitignored(root)
    local gitignore = root .. '/.gitignore'
    local lines = vim.fn.filereadable(gitignore) == 1 and vim.fn.readfile(gitignore) or {}
    for _, line in ipairs(lines) do
        if line == repo_session_name or line == '/' .. repo_session_name then
            return
        end
    end
    table.insert(lines, repo_session_name)
    vim.fn.writefile(lines, gitignore)
end

local function write_repo_session(root)
    close_sidebars()
    vim.cmd('mksession! ' .. vim.fn.fnameescape(repo_session_file(root)))
    ensure_gitignored(root)
end

local function source_session(file)
    vim.cmd('silent! source ' .. vim.fn.fnameescape(file))
    vim.v.this_session = file
end

-- Replacing the whole layout must never eat unsaved work.
local function has_unsaved_changes()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].buftype == '' and vim.bo[buf].modified then
            return true
        end
    end
    return false
end

-- Reduce the instance to a single empty buffer (terminals included): the
-- blank slate that both "clear" and "fetch" rebuild from.
local function wipe_layout()
    close_sidebars()
    vim.cmd('silent! only')
    vim.cmd('enew')
    local keep = vim.api.nvim_get_current_buf()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if buf ~= keep then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
end

-- Boot & exit ----------------------------------------------------------------

-- `nvim foo.lua` is a quick edit, not a working session: don't restore over
-- it on the way in, and don't let it overwrite a saved session on the way out.
local started_with_args = vim.fn.argc() > 0

local group = vim.api.nvim_create_augroup('RicardoSessions', { clear = true })

-- Boot: inside a repo, restore its session file or fall back to the default
-- UI; outside a repo, resume the most recent global session. This is the ONLY
-- place sessions load implicitly — changing directories later never does.
vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    nested = true, -- session :source must still fire BufRead/FileType etc.
    callback = function()
        if started_with_args then
            return
        end
        local root = git_root()
        if root then
            local file = repo_session_file(root)
            if vim.fn.filereadable(file) == 1 then
                source_session(file)
            else
                require('ricardo.gui_setup').open_default_ui()
            end
        else
            local latest = sessions.get_latest()
            if latest then
                pcall(sessions.read, latest)
            else
                require('ricardo.gui_setup').open_default_ui()
            end
        end
    end,
})

-- Exit: inside a repo, save to the repo root (created on first write and
-- gitignored); outside, save to the global directory under the cwd's name.
vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
        if started_with_args then
            return
        end
        local root = git_root()
        if root then
            pcall(write_repo_session, root)
        else
            pcall(sessions.write, vim.fn.fnamemodify(vim.fn.getcwd(), ':t'))
        end
    end,
})

-- Keymaps --------------------------------------------------------------------

-- select('write') only lists *existing* sessions, so it can't create the first
-- one. Prompt for a name instead, defaulting to the cwd's basename.
vim.keymap.set('n', '<leader>ss', function()
    vim.ui.input(
        { prompt = 'Session name: ', default = vim.fn.fnamemodify(vim.fn.getcwd(), ':t') },
        function(name)
            if name and name ~= '' then sessions.write(name) end
        end
    )
end, { noremap = true, desc = 'Write session' })

vim.keymap.set('n', '<leader>sS', function() sessions.select('write') end,
    { noremap = true, desc = 'Overwrite an existing session' })

vim.keymap.set('n', '<leader>sl', function() sessions.select('read') end,
    { noremap = true, desc = 'Load a session' })

vim.keymap.set('n', '<leader>sx', function() sessions.select('delete') end,
    { noremap = true, desc = 'Delete a session' })

-- Clear session: back to the default UI, as if booting with nothing saved.
vim.keymap.set('n', '<leader>sc', function()
    if has_unsaved_changes() then
        vim.notify('Unsaved changes — write or discard them first', vim.log.levels.WARN)
        return
    end
    wipe_layout()
    require('ricardo.gui_setup').open_default_ui()
end, { noremap = true, desc = 'Clear session (default UI)' })

-- Fetch the repo session after a :cd into a repo. Deliberately manual:
-- sessions never autoload outside the boot logic above, and leaving a repo
-- changes nothing beyond what neo-tree does on its own.
vim.keymap.set('n', '<leader>sf', function()
    local root = git_root()
    if not root then
        vim.notify('Not inside a git repo', vim.log.levels.WARN)
        return
    end
    local file = repo_session_file(root)
    if vim.fn.filereadable(file) == 0 then
        vim.notify('No session file at ' .. root, vim.log.levels.WARN)
        return
    end
    if has_unsaved_changes() then
        vim.notify('Unsaved changes — write or discard them first', vim.log.levels.WARN)
        return
    end
    wipe_layout()
    source_session(file)
end, { noremap = true, desc = 'Fetch repo session' })
