print("Applying remaps")

vim.g.mapleader = " "
-- Normal mode
vim.keymap.set("n", "<leader>d", vim.cmd.NERDTreeToggle)

-- - LSPs
