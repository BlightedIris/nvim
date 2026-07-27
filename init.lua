require('ricardo')
require('plenary')

-- LSP init
vim.lsp.enable({
    'gopls', 'rust_analyzer', 'clangd', 'basedpyright',
    'lua_ls', 'bashls', 'powershell_es',
})
-- Diagnostic box
vim.diagnostic.config({
    virtual_text = false
})


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

-- Theme
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

require('bufferline').setup(
    {
        options = {
            numbers = true
        }
    }
)

require("todo-comments").setup()
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
    sources = { default = { 'lsp', 'path', 'buffer' } },
    completion = { ghost_text = { enabled = true } },
})

local telescope = require('telescope')
local builtin = require('telescope.builtin')
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

print("Applying remaps")

vim.g.mapleader = " "

-- Terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")

-- Format
vim.keymap.set('n', '<leader>f', vim.lsp.buf.format)

-- File & text search
vim.keymap.set('n', '<leader>d', ':Neotree toggle<CR>', { noremap = true })
vim.keymap.set('n', '<leader>ff', builtin.find_files, { noremap = true })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { noremap = true })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { noremap = true })

-- LSP workflows
vim.keymap.set('n', 'gr', builtin.lsp_references, { noremap = true })
vim.keymap.set("n", "gci", vim.lsp.buf.incoming_calls) -- who calls this?
vim.keymap.set("n", "gco", vim.lsp.buf.outgoing_calls) -- what does this call?
vim.keymap.set('n', 'gd', builtin.lsp_definitions, { noremap = true })
vim.keymap.set('n', 'gi', builtin.lsp_implementations, { noremap = true })
vim.keymap.set('n', 'gs', builtin.lsp_document_symbols, { noremap = true })

-- Git
vim.keymap.set('n', '<leader>gc', builtin.git_commits, { noremap = true })
vim.keymap.set('n', '<leader>gb', builtin.git_branches, { noremap = true })

-- Diagnostic navigation (jump through errors/warnings in current file)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { noremap = true })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { noremap = true })

-- Code actions (quick fixes, refactoring)
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { noremap = true })

-- Rename symbol
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { noremap = true })

-- Type definition (what type is this?)
vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, { noremap = true })

-- Workspace symbols (search all symbols across workspace)
vim.keymap.set('n', '<leader>gw', builtin.lsp_workspace_symbols, { noremap = true })

-- Hover documentation (shows in a float)
vim.keymap.set('n', 'K', vim.lsp.buf.hover, { noremap = true })

-- TODO: Use lush to create a theme
-- TODO break down the file a bit better
-- Right now all of this is a bit messy. I'd like to have a file per plugin inside of ./lua/plugins
