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

-- global default: tabs
vim.opt.expandtab = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 0

-- .editorconfig overrides per-project (already the 0.11 default; set explicitly if you want it pinned)
vim.g.editorconfig = true
