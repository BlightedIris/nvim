print("Applying remaps")

vim.g.mapleader = " "

-- Normal mode
vim.keymap.set("n", "<leader>d", vim.cmd.NERDTreeToggle)


-- Terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")

-- - LSPs
