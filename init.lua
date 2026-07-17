require('ricardo')

-- LSP init
vim.lsp.enable({
  'gopls', 'rust_analyzer', 'clangd', 'basedpyright',
  'lua_ls', 'bashls', 'powershell_es',
})
-- Diagnostic box
vim.diagnostic.config({
  virtual_text = false
})

vim.cmd.colorscheme('melange')

-- Show line diagnostics automatically in hover window
vim.o.updatetime = 250
vim.cmd [[autocmd CursorHold,CursorHoldI * lua vim.diagnostic.open_float(nil, {focus=false})]]

-- NOTE lualine
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
    lualine_c = { {'filename', path = 2 } },
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

require('bufferline').setup(
{
    options = {
	numbers=true
    }
}
)

require('plenary')
require("todo-comments").setup()
require("blink-cmp").setup({ keymap = {
    ['<C-Space>'] = { 'show', 'show_documentation' },
    ['<Tab>']      = { 'accept', 'fallback' },
  },
  sources = { default = { 'lsp', 'path', 'buffer' } },
  completion = { ghost_text = { enabled = true } },
})

-- TODO: Use lush to create a theme
-- TODO: blink-cmd
