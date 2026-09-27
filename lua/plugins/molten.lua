-- Code execution against a jupyter kernel, plus every notebook keybinding.
--
-- Molten is a *remote plugin*: its implementation is python, running in the
-- interpreter at vim.g.python3_host_prog (set in init.lua). After adding or
-- updating it you must run :UpdateRemotePlugins once and restart, or none of
-- the :Molten* commands will exist.
--
-- The stack it sits in:
--   jupytext.nvim  — .ipynb <-> markdown on read/write
--   quarto/otter   — LSP inside the ```python fences, and the cell runner
--   molten         — runs the code, owns the kernel, draws the output
--   image.nvim     — draws plots and figures inside molten's output
local notebook = require('ricardo.notebook')

--- Options ------------------------------------------------------------------

-- Output as virtual text under the cell, VSCode-style: it stays visible after
-- the cursor moves away instead of living in a float that closes on BufLeave.
vim.g.molten_virt_text_output = true
vim.g.molten_auto_open_output = false
-- Molten's own docs recommend turning this on for jupytext/quarto buffers, so
-- output covers the closing ``` instead of pushing it down. Do not: with
-- render-markdown loaded that fence line carries `conceal_lines`, and neovim
-- does not draw the virtual lines of a concealed line -- every cell would run
-- and print into thin air.
vim.g.molten_virt_lines_off_by_1 = false
vim.g.molten_virt_text_max_lines = 24
vim.g.molten_wrap_output = true

vim.g.molten_image_provider = 'image.nvim'

-- The output window (<leader>no) is for reading long output; cap it so it
-- can't swallow the screen, and let it report what got cut off.
vim.g.molten_output_win_max_height = 24
vim.g.molten_output_show_more = true
vim.g.molten_output_show_exec_time = true
vim.g.molten_use_border_highlights = true

-- Default 500ms makes short cells feel laggy -- this is how often molten polls
-- the kernel for updates.
vim.g.molten_tick_rate = 200

--- Keymaps ------------------------------------------------------------------
-- All buffer-local to notebook buffers (lua/ricardo/notebook.lua:is_notebook):
-- every one of these needs a cell to act on, and half of them need otter
-- activated, which only happens there.
--
-- <leader>n* is the notebook family; the <CR> variants mirror VSCode's
-- notebook keys and need a terminal that sends modified <CR> -- Ghostty
-- speaks the kitty keyboard protocol, so neovim can tell them apart from a
-- plain <CR>.

local function runner()
    return require('quarto.runner')
end

local function notebook_keys(buf)
    local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = 'Notebook: ' .. desc })
    end

    -- VSCode's notebook <CR> keys
    map('n', '<C-CR>', function() runner().run_cell() end, 'run cell')
    map('n', '<S-CR>', function()
        runner().run_cell()
        notebook.goto_cell(1)
    end, 'run cell and advance')
    map('n', '<A-CR>', function()
        runner().run_cell()
        notebook.insert_code_cell(false)
    end, 'run cell and insert below')
    map('v', '<C-CR>', function() runner().run_range() end, 'run selection')

    -- Cell motion. `n` is the one bracketed suffix mini.bracketed leaves free.
    map('n', ']n', function() notebook.goto_cell(1) end, 'next code cell')
    map('n', '[n', function() notebook.goto_cell(-1) end, 'previous code cell')

    -- Running code
    map('n', '<leader>nr', function() runner().run_cell() end, 'run cell')
    map('v', '<leader>nr', function() runner().run_range() end, 'run selection')
    map('n', '<leader>nR', function() runner().run_all() end, 'run all cells')
    map('n', '<leader>na', function() runner().run_above() end, 'run cells above (inclusive)')
    map('n', '<leader>nb', function() runner().run_below() end, 'run cells below (inclusive)')
    map('n', '<leader>nl', function() runner().run_line() end, 'run line')

    -- Kernel lifecycle
    map('n', '<leader>nk', notebook.init_kernel, 'start kernel (auto-detected)')
    map('n', '<leader>nK', ':MoltenInit<CR>', 'start kernel (pick from list)')
    map('n', '<leader>nx', ':MoltenInterrupt<CR>', 'interrupt execution')
    map('n', '<leader>nX', ':MoltenRestart!<CR>', 'restart kernel and clear outputs')
    map('n', '<leader>nq', ':MoltenDeinit<CR>', 'shut the kernel down')

    -- Output
    map('n', '<leader>no', ':noautocmd MoltenEnterOutput<CR>', 'open/enter output window')
    map('n', '<leader>nh', ':MoltenHideOutput<CR>', 'hide output window')
    map('n', '<leader>ny', ':MoltenYankOutput<CR>', 'yank output')
    map('n', '<leader>nc', ':MoltenDelete<CR>', "clear this cell's output")
    map('n', '<leader>nC', ':MoltenDelete!<CR>', 'clear all outputs')
    map('n', '<leader>ne', ':MoltenExportOutput!<CR>', 'write outputs into the .ipynb')
    map('n', '<leader>nE', ':MoltenImportOutput<CR>', 'load outputs from the .ipynb')

    -- Editing
    map('n', '<leader>ni', function() notebook.insert_code_cell(false) end, 'insert code cell below')
    map('n', '<leader>nI', function() notebook.insert_code_cell(true) end, 'insert code cell above')
    map('n', '<leader>nm', function() notebook.insert_markdown_cell(false) end, 'insert markdown cell below')
    map('n', '<leader>nM', function() notebook.insert_markdown_cell(true) end, 'insert markdown cell above')
end

--- Autocommands -------------------------------------------------------------

local group = vim.api.nvim_create_augroup('RicardoNotebook', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'markdown', 'quarto' },
    callback = function(args)
        if notebook.is_notebook(args.buf) then
            notebook_keys(args.buf)
        end
    end,
})

-- Molten doubles as a scratch REPL for plain .py files, where persistent
-- virtual text under every line you run is noise -- there the float is
-- better. Notebooks want the opposite. MoltenUpdateOption is the only way to
-- change these once a kernel is running; the g: vars only apply before that.
local function output_style(virt)
    if notebook.initialized() then
        vim.fn.MoltenUpdateOption('virt_text_output', virt)
    else
        vim.g.molten_virt_text_output = virt
    end
end

vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    pattern = { '*.py' },
    callback = function(args)
        -- otter's hidden buffers are named <file>.otter.py; they are not
        -- something the user ever looks at
        if not args.file:match('%.otter%.') then
            output_style(false)
        end
    end,
})

vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    pattern = { '*.ipynb', '*.qmd' },
    callback = function(args)
        if not args.file:match('%.otter%.') then
            output_style(true)
        end
    end,
})

-- Opening a notebook should show the outputs that are already saved in it,
-- the way VSCode does -- that needs a kernel attached to the buffer, so start
-- the resolved one and import. Skipped entirely when no kernel is available,
-- rather than blocking the open with molten's picker.
local function init_notebook_buffer()
    vim.schedule(function()
        if notebook.initialized() then
            return
        end
        if not notebook.resolve_kernel() then
            return
        end
        notebook.init_kernel()
        pcall(vim.cmd, 'MoltenImportOutput')
    end)
end

vim.api.nvim_create_autocmd('BufAdd', {
    group = group,
    pattern = { '*.ipynb' },
    callback = init_notebook_buffer,
})

-- BufAdd doesn't fire for the file named on the command line (`nvim x.ipynb`),
-- so catch that first BufEnter too.
vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    pattern = { '*.ipynb' },
    callback = function()
        if vim.v.vim_did_enter ~= 1 then
            init_notebook_buffer()
        end
    end,
})

-- :w converts the buffer back to .ipynb but jupytext cannot know about output
-- produced this session -- molten writes it in afterwards, so a saved notebook
-- carries the results you just ran.
vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = { '*.ipynb' },
    callback = function()
        if notebook.initialized() then
            pcall(vim.cmd, 'MoltenExportOutput!')
        end
    end,
})
