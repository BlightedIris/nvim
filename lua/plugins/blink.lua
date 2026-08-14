require("blink-cmp").setup({
    fuzzy = {
        implementation = 'lua',
    },
    keymap = {
        ['<C-Space>'] = { 'show', 'show_documentation' },
        ['<Tab>']     = { 'accept', 'fallback' },
    },
    sources = {
        default = { 'lsp', 'codecompanion', 'path', 'buffer' },
        per_filetype = { codecompanion = { "codecompanion" } },
        providers = {},
    },
    completion = {
        ghost_text = { enabled = true },
        trigger = { prefetch_on_insert = false }, -- avoid firing a request on every insert-mode entry
    },
})
