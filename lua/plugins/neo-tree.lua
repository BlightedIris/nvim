require('neo-tree').setup({
    filesystem = {
        filtered_items = {
            visible = false,
            hide_dotfiles = false,
        },
        enable_icons = true,
        root_dir = function()
            return vim.fn.getcwd()
        end,
        follow_current_file = { enabled = true },
    },
})

