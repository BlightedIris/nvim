require('blink-cmp').build():pwait()

require("blink-cmp").setup({
    fuzzy = {
        implementation = 'rust',
        sorts = {
            'exact',
            -- defaults
            'score',
            'sort_text',
        },
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
        menu = { border = 'single' },
        ghost_text = { enabled = true },
        documentation = { auto_show = false, window = { border = 'single' } },
        trigger = { prefetch_on_insert = false }, -- avoid firing a request on every insert-mode entry
    },
})
