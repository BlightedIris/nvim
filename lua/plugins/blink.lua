require("blink-cmp").setup({
    fuzzy = {
        implementation = 'lua',
    },
    keymap = {
        ['<C-Space>'] = { 'show', 'show_documentation' },
        ['<Tab>']     = { 'accept', 'fallback' },
        ["<Right>"]   = { 'accept', 'fallback' },
        ["<CR>"]      = { 'accept', 'fallback' },
    },
    sources = { default = { 'lsp', 'path', 'buffer' }, per_filetype = { codecompanion = { "codecompanion" }} },
    completion = { ghost_text = { enabled = true } },
})

