require("blink-cmp").setup({
    fuzzy = {
        implementation = 'lua',
    },
    keymap = {
        ['<C-Space>'] = { 'show', 'show_documentation' },
        ['<Tab>']     = { 'accept', 'fallback' },
        ["<CR>"]      = { 'accept', 'fallback' },
    },
    sources = {
        default = { 'lsp', 'codecompanion', 'path', 'buffer', 'minuet' },
        per_filetype = { codecompanion = { "codecompanion" } },
        providers = {
            minuet = {
                name = 'minuet',
                module = 'minuet.blink',
                async = true,
                timeout_ms = 3000, -- matches minuet's default request_timeout (3s)
                score_offset = 50, -- prioritize FIM ghost text over LSP/buffer matches
            },
        },
    },
    completion = {
        ghost_text = { enabled = true },
        trigger = { prefetch_on_insert = false }, -- avoid firing a request on every insert-mode entry
    },
})

