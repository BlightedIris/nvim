-- Terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")
local shell = vim.fn.has("win32") == 1 and "powershell" or vim.o.shell
print("Shell set to:")
print(shell)
vim.keymap.set("n", "<leader>t", function() vim.cmd.terminal(shell) end)

local builtin = require('telescope.builtin')
-- Format: uses the attached LSP's built-in formatting capability.
vim.keymap.set({ 'n', 'v' }, '<C-s>', function()
    vim.lsp.buf.format({ async = true })
end, { noremap = true, desc = 'Format buffer/selection' })

-- Window navigation
vim.keymap.set('n', '<C-h>', '<C-w>h', { noremap = true })
vim.keymap.set('n', '<C-j>', '<C-w>j', { noremap = true })
vim.keymap.set('n', '<C-k>', '<C-w>k', { noremap = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { noremap = true })

-- Move the selected lines up/down, reindenting and reselecting
vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv", { noremap = true, silent = true })
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { noremap = true, silent = true })

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

-- Diagnostic navigation (jump through errors/warnings in current file).
-- Uppercase so mini.bracketed keeps the lowercase `[d` / `]d` of its
-- `[`/`]` + suffix family (see lua/plugins/mini-bracketed.lua)
vim.keymap.set('n', '[D', function() vim.diagnostic.jump({ count = -1 }) end, { noremap = true })
vim.keymap.set('n', ']D', function() vim.diagnostic.jump({ count = 1 }) end, { noremap = true })


-- Keep the cursor centered on half-page jumps and search so the match
-- always lands with context on both sides instead of at the screen edge
vim.keymap.set('n', '<C-d>', '<C-d>zz', { noremap = true })
vim.keymap.set('n', '<C-u>', '<C-u>zz', { noremap = true })
vim.keymap.set('n', 'n', 'nzzzv', { noremap = true })
vim.keymap.set('n', 'N', 'Nzzzv', { noremap = true })

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


vim.keymap.set('n', '<leader>cd', ':ChatDelete<CR>',
    { noremap = true, silent = true, desc = 'Select saved chats to delete' })
vim.keymap.set('n', '<leader>cda', ':ChatClearAll<CR>', { noremap = true })
vim.keymap.set('n', '<leader>cr', ':CodeCompanionRestart<CR>', { noremap = true })

-- Open the remap cheatsheet (resolved via stdpath so it works on any machine)
vim.keymap.set('n', '<leader>?', function()
    vim.cmd.edit(vim.fn.stdpath('config') .. '/REMAPS.md')
end, { noremap = true, desc = 'Open remap cheatsheet' })
