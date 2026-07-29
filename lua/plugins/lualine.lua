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
        lualine_c = { { 'filename', path = 2 } },
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

    extensions = { 'fugitive', 'nvim-tree' },
})

