-- Colours
vim.api.nvim_win_set_option(0, "termguicolors", true)

-- Window-local options
vim.api.nvim_win_set_option(0, "number", true)
vim.api.nvim_win_set_option(0, "relativenumber", true)
vim.api.nvim_win_set_option(0, "signcolumn", "yes")
vim.api.nvim_win_set_option(0, "numberwidth", 2)
-- Buffer-local options
vim.api.nvim_buf_set_option(0, "expandtab", false)
vim.api.nvim_buf_set_option(0, "softtabstop", 4)
vim.api.nvim_buf_set_option(0, "tabstop", 4)
vim.api.nvim_buf_set_option(0, "shiftwidth", 4)
vim.api.nvim_buf_set_option(0, "smartindent", true)
-- Whitespace visualization
vim.opt.list = true
vim.opt.listchars = { tab = "· ", trail = "_" }
