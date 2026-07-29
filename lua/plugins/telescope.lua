local telescope = require('telescope')
local actions = require('telescope.actions')

telescope.setup({
    defaults = {
        mappings = {
            i = {
                ['<C-q>'] = actions.send_to_qflist + actions.open_qflist,
            },
        },
        layout_strategy = 'vertical',
        layout_config = {
            vertical = { width = 0.9, height = 0.95, preview_height = 0.6 },
        },
    },
    pickers = {
        find_files = {
            hidden = true,
        },
    },
})

