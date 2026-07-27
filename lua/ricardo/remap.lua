print("Applying remaps")

vim.g.mapleader = " "

-- Navigate
vim.keymap.set("n", "<leader>d", ':Ex<CR>')

-- Terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")

-- LSPs & diagnostics
vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls)  -- who calls this?
vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls)  -- what does this call?

-- Format
vim.keymap.set('n', '<leader>f', vim.lsp.buf.format)
