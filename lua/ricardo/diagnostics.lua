-- Diagnostics show up in a floating window on hover, not signs or virtual
-- text. The float only opens on CursorHold in normal mode (not
-- CursorHoldI), so it never competes with the insert-mode blink-cmp
-- completion menu, and it closes itself as soon as the cursor moves so it
-- never lingers over other floats (K hover, signature help).
local M = {}

local group = vim.api.nvim_create_augroup('RicardoDiagnosticFloat', { clear = true })
local float_win = nil

-- True from the moment K is pressed until the cursor moves away. Neovim
-- tracks only one floating-preview window per buffer (see
-- vim.lsp.util.open_floating_preview), so if CursorHold fires again while a
-- requested hover is still awaiting its LSP response, the diagnostic float
-- would steal that slot and clobber the hover window the instant it opens.
local hover_active = false

function M.close_float()
    if float_win and vim.api.nvim_win_is_valid(float_win) then
        vim.api.nvim_win_close(float_win, false)
    end
    float_win = nil
    hover_active = false
end

-- Use instead of vim.lsp.buf.hover() directly so the CursorHold diagnostic
-- float doesn't fight it while the hover request is in flight.
function M.request_hover()
    if float_win and vim.api.nvim_win_is_valid(float_win) then
        vim.api.nvim_win_close(float_win, false)
    end
    float_win = nil
    hover_active = true
    vim.lsp.buf.hover()
end

vim.diagnostic.config({
    virtual_text = false,
    signs = false,
    underline = true,
    update_in_insert = false,
})

vim.o.updatetime = 250

vim.api.nvim_create_autocmd('CursorHold', {
    group = group,
    desc = 'Show diagnostics for the line under the cursor in a floating window',
    callback = function()
        -- Don't cover an open completion menu, and don't clobber a hover
        -- float that's still waiting on its LSP response.
        if vim.fn.pumvisible() == 1 or hover_active then
            return
        end
        local _, winid = vim.diagnostic.open_float(nil, { focus = false, scope = 'cursor' })
        float_win = winid
    end,
})

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufLeave', 'WinLeave' }, {
    group = group,
    desc = 'Close the diagnostic hover float once the cursor leaves',
    callback = M.close_float,
})

return M
