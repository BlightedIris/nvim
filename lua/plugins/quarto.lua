-- LSP inside notebook code cells, and the cell runner.
--
-- A notebook opened through jupytext is a markdown buffer, and basedpyright
-- has nothing to say about markdown. otter.nvim closes that gap: it keeps a
-- hidden, synchronised python buffer containing just the code from the
-- ```python fences and forwards completion, hover, go-to-definition, rename
-- and diagnostics to it -- so cells behave like the .py file they used to be.
--
-- quarto-nvim sits on top and provides the cell runner (which cells overlap
-- the cursor/selection, and where to send them). Its `molten` method calls
-- MoltenEvaluateRange, so run-cell/above/below/all all end up in the same
-- kernel that lua/plugins/molten.lua manages. Quarto the CLI is not needed --
-- nothing here renders or previews quarto documents.
require('otter').setup({
    lsp = {
        -- default is BufWritePost only, which in a notebook means no
        -- diagnostics until you save (and saving round-trips the whole file
        -- through jupytext). Leaving insert is the cheap middle ground.
        diagnostic_update_events = { 'BufWritePost', 'InsertLeave' },
    },
    buffers = {
        set_filetype = true,
    },
})

require('quarto').setup({
    lspFeatures = {
        enabled = true,
        -- 'curly' only matches quarto's ```{python} fences; notebooks
        -- converted by jupytext use plain ```python
        chunks = 'all',
        -- nil = every language found in the document, so a julia or R
        -- notebook gets the same treatment if those servers are installed
        languages = nil,
        diagnostics = { enabled = true, triggers = { 'BufWritePost' } },
        completion = { enabled = true },
    },
    codeRunner = {
        enabled = true,
        default_method = 'molten',
        never_run = { 'yaml' },
    },
})
