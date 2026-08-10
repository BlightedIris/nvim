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
            { 'filename', path = 2 },
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

