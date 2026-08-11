-- Lists the windows in the current tabpage as "1 2 [3] 4", bracketing the
-- currently focused window, so its number can be used directly with
-- `{N}<C-w>w` instead of cycling with `<C-w>w`/`<C-w>h` etc.
local function window_list()
    local cur_win = vim.api.nvim_get_current_win()
    local wins = vim.tbl_filter(function(win)
        return vim.api.nvim_win_get_config(win).relative == ''
    end, vim.api.nvim_tabpage_list_wins(0))
    table.sort(wins, function(a, b)
        return vim.api.nvim_win_get_number(a) < vim.api.nvim_win_get_number(b)
    end)

    local parts = {}
    for _, win in ipairs(wins) do
        local number = vim.api.nvim_win_get_number(win)
        parts[#parts + 1] = win == cur_win and ('[' .. number .. ']') or tostring(number)
    end
    return table.concat(parts, ' ')
end

local function winnr()
    return tostring(vim.fn.winnr())
end

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
            {
                window_list,
                cond = function() return #vim.api.nvim_tabpage_list_wins(0) > 1 end,
            },
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

    -- Per-window number shown at the top of every split.
    winbar = {
        lualine_c = { winnr },
    },
    inactive_winbar = {
        lualine_c = { winnr },
    },

    extensions = { 'fugitive', 'nvim-tree' },
})

