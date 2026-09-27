-- Turn on otter's embedded-language LSP for notebook buffers.
--
-- quarto-nvim only activates itself in `quarto` filetype buffers, but a
-- notebook opened through jupytext.nvim is filetype `markdown` (see
-- lua/plugins/jupytext.lua), so activation has to happen here.
--
-- Deliberately scoped to notebooks rather than all markdown: activation spins
-- up a hidden buffer and an LSP client per embedded language, which is not
-- something a README should pay for.
if require('ricardo.notebook').is_notebook(0) then
    require('quarto').activate()
end

-- <S-Tab> swaps this window between the markdown source and a `glow` render
-- of it (lua/ricardo/markdown_preview.lua). Buffer-local rather than global:
-- the render is read-only, so the binding only makes sense where there is
-- markdown to render. The reverse binding lives on the render buffer itself.
--
-- The require is inside the callback, not resolved here: an ftplugin is
-- re-sourced from disk for every markdown buffer while `require` results are
-- cached for the life of the session, so resolving it at source time turns
-- any stale cache into an error on *opening a file* rather than on pressing
-- the key.
vim.keymap.set('n', '<S-Tab>', function()
    require('ricardo.markdown_preview').toggle()
end, { buffer = true, desc = 'Toggle glow markdown preview' })
