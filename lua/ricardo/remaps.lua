-- Terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")
-- Bottom terminal split at 25% height (same one the default UI opens)
vim.keymap.set("n", "<leader>t", function() require('ricardo.gui_setup').open_terminal() end)

-- Surround a visual selection, mirroring the vi(/va( idea: select, then
-- s + i/a + char. `i` hugs the selection tight `(sel)`, `a` pads it
-- `( sel )`; typing either half of a bracket pair works, the matching
-- half is filled in. Non-bracket chars (quotes etc.) repeat on both sides.
-- Delegates to mini.surround's add, so multiline/blockwise selections work.
do
    local open_to_close = { ['('] = ')', ['['] = ']', ['{'] = '}', ['<'] = '>' }
    local close_to_open = {}
    for o, c in pairs(open_to_close) do close_to_open[c] = o end

    -- mini.surround's own convention: an opening char pads, a closing char
    -- hugs. So i/a just normalizes whatever was typed to the right half.
    local function surround_selection(padded)
        local ok, char = pcall(vim.fn.getcharstr)
        if not ok or char == vim.keycode('<Esc>') then return end
        if padded then
            char = close_to_open[char] or char
        else
            char = open_to_close[char] or char
        end
        vim.api.nvim_feedkeys(
            ':' .. vim.keycode('<C-u>') .. 'lua MiniSurround.add("visual")\r' .. char,
            'n', false)
    end

    vim.keymap.set('x', 'si', function() surround_selection(false) end,
        { desc = 'Surround selection (tight)' })
    vim.keymap.set('x', 'sa', function() surround_selection(true) end,
        { desc = 'Surround selection (padded)' })
end

local builtin = require('telescope.builtin')
-- Format: uses the attached LSP's built-in formatting capability.
vim.keymap.set({ 'n', 'v' }, '<C-s>', function()
    vim.lsp.buf.format({ async = true })
end, { noremap = true, desc = 'Format buffer/selection' })

-- Window navigation
vim.keymap.set('n', '<C-h>', '<C-w>h', { noremap = true })
vim.keymap.set('n', '<C-j>', '<C-w>j', { noremap = true })
vim.keymap.set('n', '<C-k>', '<C-w>k', { noremap = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { noremap = true })

-- Move the current window to the far left/bottom/top/right. Shifted chords
-- since the unshifted ones navigate; needs a terminal with the extended-keys
-- protocol to tell <C-S-l> apart from <C-l>.
vim.keymap.set('n', '<C-S-h>', '<C-w>H', { noremap = true })
vim.keymap.set('n', '<C-S-j>', '<C-w>J', { noremap = true })
vim.keymap.set('n', '<C-S-k>', '<C-w>K', { noremap = true })
vim.keymap.set('n', '<C-S-l>', '<C-w>L', { noremap = true })

-- Move the selected lines up/down, reindenting and reselecting
vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv", { noremap = true, silent = true })
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { noremap = true, silent = true })

-- Toggle comment on the current line / selection. Delegates to the built-in
-- gcc/gc mappings (hence remap = true), so it stays filetype-aware via
-- 'commentstring'. Terminals without the extended-keys protocol deliver
-- Ctrl+/ as <C-_>, so both chords are bound.
for _, key in ipairs({ '<C-/>', '<C-_>' }) do
    vim.keymap.set('n', key, 'gcc', { remap = true, desc = 'Toggle comment line' })
    vim.keymap.set('x', key, 'gc', { remap = true, desc = 'Toggle comment selection' })
end

-- File & text search
vim.keymap.set('n', '<leader>d', ':Neotree toggle<CR>', { noremap = true })
vim.keymap.set('n', '<leader>ff', builtin.find_files, { noremap = true })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { noremap = true })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { noremap = true })

-- LSP workflows
vim.keymap.set('n', 'gr', builtin.lsp_references, { noremap = true })
vim.keymap.set("n", "gci", vim.lsp.buf.incoming_calls) -- who calls this?
vim.keymap.set("n", "gco", vim.lsp.buf.outgoing_calls) -- what does this call?
vim.keymap.set('n', 'gd', builtin.lsp_definitions, { noremap = true })
vim.keymap.set('n', 'gi', builtin.lsp_implementations, { noremap = true })
vim.keymap.set('n', 'gs', builtin.lsp_document_symbols, { noremap = true })

-- Git
vim.keymap.set('n', '<leader>gc', builtin.git_commits, { noremap = true })
vim.keymap.set('n', '<leader>gb', builtin.git_branches, { noremap = true })

-- Diagnostic navigation (jump through errors/warnings in current file).
-- Uppercase so mini.bracketed keeps the lowercase `[d` / `]d` of its
-- `[`/`]` + suffix family (see lua/plugins/mini-bracketed.lua)
vim.keymap.set('n', '[D', function() vim.diagnostic.jump({ count = -1 }) end, { noremap = true })
vim.keymap.set('n', ']D', function() vim.diagnostic.jump({ count = 1 }) end, { noremap = true })


-- Keep the cursor centered on half-page jumps and search so the match
-- always lands with context on both sides instead of at the screen edge
vim.keymap.set('n', '<C-d>', '<C-d>zz', { noremap = true })
vim.keymap.set('n', '<C-u>', '<C-u>zz', { noremap = true })
vim.keymap.set('n', 'n', 'nzzzv', { noremap = true })
vim.keymap.set('n', 'N', 'Nzzzv', { noremap = true })

-- Code actions (quick fixes, refactoring)
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { noremap = true })

-- Rename symbol
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { noremap = true })

-- Type definition (what type is this?)
vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, { noremap = true })

-- Workspace symbols (search all symbols across workspace)
vim.keymap.set('n', '<leader>gw', builtin.lsp_workspace_symbols, { noremap = true })

-- Hover documentation (shows in a float)
vim.keymap.set('n', 'K', vim.lsp.buf.hover, { noremap = true })


vim.keymap.set('n', '<leader>cd', ':ChatDelete<CR>',
    { noremap = true, silent = true, desc = 'Select saved chats to delete' })
vim.keymap.set('n', '<leader>cda', ':ChatClearAll<CR>', { noremap = true })
vim.keymap.set('n', '<leader>cr', ':CodeCompanionRestart<CR>', { noremap = true })

-- Open the remap cheatsheet (resolved via stdpath so it works on any machine)
vim.keymap.set('n', '<leader>?', function()
    vim.cmd.edit(vim.fn.stdpath('config') .. '/REMAPS.md')
end, { noremap = true, desc = 'Open remap cheatsheet' })
