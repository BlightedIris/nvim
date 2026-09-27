-- Notebook file format conversion. Opening a .ipynb hands the JSON to the
-- `jupytext` CLI and puts its markdown rendering in the buffer instead; :w
-- converts back and merges the result into the original .ipynb, leaving
-- outputs that are already in the file untouched.
--
-- Markdown (rather than jupytext's default "hydrogen" .py-with-`# %%`) is
-- what makes the buffer read like VSCode's notebook view: prose cells are
-- real markdown, rendered by render-markdown.nvim, and code cells are
-- ```python fences. The cost is that the buffer is no longer a .py file, so
-- the python LSP can't see the code -- lua/plugins/quarto.lua fixes that.
--
-- Requires the `jupytext` CLI on PATH (installed with `uv tool install
-- jupytext`, which lands in ~/.local/bin -- prepended to PATH by init.lua).
require('jupytext').setup({
    style = 'markdown',
    output_extension = 'md',
    force_ft = 'markdown',
})
