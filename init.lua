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
