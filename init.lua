require('ricardo')

-- plugins
require('lualine').setup()
require('bufferline').setup()
require('plenary')
require("todo-comments").setup()
-- require("frizbee")
require("blink-cmp").setup({ keymap = {
    ['<C-Space>'] = { 'show', 'show_documentation' },
    ['<CR>']      = { 'accept', 'fallback' },
    ['<Tab>']     = { 'select_next', 'snippet_forward', 'fallback' },
    ['<S-Tab>']   = { 'select_prev', 'snippet_backward', 'fallback' },
    ['<C-e>']     = { 'hide' },
    ['<C-n>']     = { 'select_next', 'fallback' },
    ['<C-p>']     = { 'select_prev', 'fallback' },
  },
  sources = { default = { 'lsp', 'path', 'buffer' } },
  completion = { ghost_text = { enabled = true } },
})
vim.lsp.enable('basedpyright')

-- TODO: Use lush to create a theme
-- TODO: blink-cmp 
