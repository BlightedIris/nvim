-- `setup()` itself resolves the fuzzy matcher: it checks target/release for a
-- locally built library and only falls back to downloading a prebuilt binary if
-- that's missing. The Rust library is built from source here via
-- `cargo build --release` (see README), which also writes target/release/version
-- with the checked-out SHA so blink knows the build is current.
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
        -- Windows Terminal/ConPTY sends NUL for Ctrl+Space, which Neovim sees as <C-@>
        ['<C-@>']     = { 'show', 'show_documentation' },
        ['<Tab>']     = { 'accept', 'fallback' },
    },
    sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
        per_filetype = { codecompanion = { 'codecompanion' } },
        providers = {
            codecompanion = {
                name = 'CodeCompanion',
                module = 'codecompanion.providers.completion.blink',
                score_offset = 100,
            },
        },
    },
    snippets = { preset = 'default' }, -- friendly-snippets is installed
    completion = {
        menu = { border = 'single' },
        ghost_text = { enabled = true },
        documentation = { auto_show = false, window = { border = 'single' } },
        trigger = { prefetch_on_insert = false },
    },
    signature = { enabled = true },
})
