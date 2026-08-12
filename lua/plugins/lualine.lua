local function is_codecompanion_chat()
    return vim.bo.filetype == 'codecompanion'
end

-- Shows "[CodeCompanion] {source} - {model}" instead of a filename/path,
-- since chat buffers have neither -- lets you see who you're talking to
-- without `ga`. Reads from codecompanion's own metadata table
-- (_G.codecompanion_chat_metadata), keyed by adapter.formatted_name (e.g.
-- "Ollama", "Claude Code") slugified into the source/model text below.
--
-- HTTP adapters (ollama, openai, ...) report a real selected model via
-- adapter.schema.model.default, so those show as `ollama - gpt-oss:20b`.
-- ACP adapters (claude_code and similar) negotiate their model over the ACP
-- connection at runtime; codecompanion falls back to the literal string
-- "default" there once connected but before that negotiation lands, so it's
-- not a fact worth surfacing. Those instead show as `API - claude_code`,
-- source "API" since the connection is a hosted API rather than a local
-- model host, and the adapter's own name standing in for the model.
local function codecompanion_model()
    local metadata = _G.codecompanion_chat_metadata and _G.codecompanion_chat_metadata[vim.api.nvim_get_current_buf()]
    local adapter = metadata and metadata.adapter
    if not adapter or not adapter.name then
        return '[CodeCompanion] - ?'
    end

    local slug = adapter.name:lower():gsub('%s+', '_')

    if adapter.type == 'acp' then
        return '[CodeCompanion] API - ' .. slug
    end

    return '[CodeCompanion] ' .. slug .. ' - ' .. (adapter.model or '?')
end

-- Caches the machine's default WSL distro name (queried once via `wsl -l`)
-- for terminal buffers that were started with a bare `wsl` (no `-d`).
local wsl_default_distro
local function get_wsl_default_distro()
    if wsl_default_distro then
        return wsl_default_distro
    end

    local ok, out = pcall(vim.fn.system, { 'wsl.exe', '-l', '-q' })
    if ok and vim.v.shell_error == 0 then
        for line in out:gsub('%z', ''):gmatch('[^\r\n]+') do
            line = vim.trim(line)
            if line ~= '' then
                wsl_default_distro = line
                break
            end
        end
    end

    wsl_default_distro = wsl_default_distro or 'wsl'
    return wsl_default_distro
end

-- Terminal buffer names look like `term://{cwd}//{pid}:{cmd}`, where {cmd} is
-- whatever was passed to `:terminal`. Reduce that down to just the process
-- name, e.g. "powershell", "python" -- and for `wsl`, name the distro too.
local function terminal_display_name(buf)
    local cmd = vim.api.nvim_buf_get_name(buf):match('^term://.-//%d+:(.*)$') or 'terminal'
    local exe = cmd:match('^%S+') or cmd
    exe = (exe:match('([^\\/]+)$') or exe):gsub('%.exe$', '')

    if exe == 'wsl' then
        local distro = cmd:match('%-d%s+(%S+)') or cmd:match('%-%-distribution%s+(%S+)')
        return 'wsl (' .. (distro or get_wsl_default_distro()) .. ')'
    end

    return exe
end

-- Winbar title shown at the top of every split: bare filename for normal
-- buffers, process name for terminals, and fixed labels for the "chrome"
-- filetypes that don't have a meaningful filename of their own.
local function winbar_title()
    local buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype

    if ft == 'neo-tree' then
        return 'workplace'
    end

    if ft == 'codecompanion' then
        return 'Chat'
    end

    if vim.bo[buf].buftype == 'terminal' then
        return terminal_display_name(buf)
    end

    local name = vim.api.nvim_buf_get_name(buf)
    return name == '' and '[No Name]' or vim.fn.fnamemodify(name, ':t')
end

require('lualine').setup({
    options = {
        theme = 'auto',
        icons_enabled = true,
        section_separators = { left = '', right = '' },
        component_separators = { left = '', right = '' },
        globalstatus = true,
        disabled_filetypes = { statusline = { 'NvimTree' } },
    },
    sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch' },
        lualine_c = {
            { codecompanion_model, cond = is_codecompanion_chat },
            { 'filename', path = 2, cond = function() return not is_codecompanion_chat() end },
        },
        lualine_x = {
            'encoding',
            {
                'fileformat',
                symbols = { unix = 'LF', dos = 'CRLF', mac = 'CR' }
            }
        },
        lualine_y = { 'lsp_status' },
        lualine_z = { 'location', 'searchcount' },
    },

    -- Per-window title shown at the top of every split.
    winbar = {
        lualine_a = { winbar_title },
    },
    inactive_winbar = {
        lualine_a = { winbar_title },
    },

    extensions = { 'fugitive', 'nvim-tree' },
})

