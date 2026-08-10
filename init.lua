vim.g.mapleader = " "

require('plugins')
require('ricardo')

-- Diagnostic box
vim.diagnostic.config({
    virtual_text = false
})

-- Theme
vim.cmd.colorscheme('kanagawa-dragon')

-- Show line diagnostics automatically in hover window
vim.o.updatetime = 250
vim.cmd [[autocmd CursorHold,CursorHoldI * lua vim.diagnostic.open_float(nil, {focus=false})]]

-- NOTE lualine
print("Applying remaps")

-- Terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")
local shell = vim.fn.has("win32") == 1 and "powershell" or vim.o.shell
print("Shell set to:")
print(shell)
vim.keymap.set("n", "<leader>t", function() vim.cmd.terminal(shell) end)

local builtin = require('telescope.builtin')
-- Format
vim.keymap.set('n', '<C-s>', vim.lsp.buf.format)

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
