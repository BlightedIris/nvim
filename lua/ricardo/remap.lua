print("Applying remaps")

vim.g.mapleader = " "

-- Normal mode
vim.keymap.set("n", "<leader>d", vim.cmd.NERDTreeToggle)

-- Terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")

-- LSPs & diagnostics
vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls)  -- who calls this?
vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls)  -- what does this call?
