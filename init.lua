vim.g.mapleader = " "

-- ~/.local/bin is where hand-installed tools land (e.g. verible), but not
-- every login shell puts it on PATH. Prepend it before plugins load so
-- executable() checks (lsp.lua's verible gate) and :terminal both see it.
local local_bin = vim.fn.expand('~/.local/bin')
if vim.fn.isdirectory(local_bin) == 1 and not vim.env.PATH:find(local_bin, 1, true) then
    vim.env.PATH = local_bin .. ':' .. vim.env.PATH
end

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
