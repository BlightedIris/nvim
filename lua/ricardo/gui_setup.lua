-- Colours
vim.api.nvim_win_set_option(0, "termguicolors", true)

-- Window-local options
vim.api.nvim_win_set_option(0, "number", true)
vim.api.nvim_win_set_option(0, "relativenumber", true)
vim.api.nvim_win_set_option(0, "signcolumn", "yes")
vim.api.nvim_win_set_option(0, "numberwidth", 2)

-- Buffer-local options
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.api.nvim_buf_set_option(0, "smartindent", true)

-- Whitespace visualization
vim.opt.list = true
vim.opt.listchars = { tab = "· ", trail = "_" }

local M = {}

-- Default chrome: neo-tree (left) | editor over terminal (middle) | AI chat
-- (right). Works on top of whatever layout exists, so the session logic
-- (lua/plugins/mini-sessions.lua) uses it both for the blank-slate boot /
-- <leader>sc and to re-dress a restored session, which carries only file
-- windows (neo-tree and terminals don't serialize into session files).
-- Bottom terminal: splits below the current file window at a quarter of the
-- vertical space, so it shares that window's width and never slides under
-- the neo-tree sidebar (a botright split would span the whole screen).
-- Leaves the cursor in the terminal; also bound to <leader>t (remaps.lua).
M.open_terminal = function()
    local shell = vim.fn.has("win32") == 1 and "powershell" or vim.o.shell
    -- Invoked from a sidebar or another terminal: hop back to the last-used
    -- window first so the split lands under the editor, not the sidebar.
    if vim.bo.buftype ~= "" or vim.bo.filetype == "neo-tree" then
        vim.cmd.wincmd("p")
    end
    vim.cmd("belowright " .. math.floor(vim.o.lines * 0.25) .. "split")
    vim.cmd.terminal(shell)
end

M.open_chrome = function()
    local editor_win = vim.api.nvim_get_current_win()

    M.open_terminal()
    vim.api.nvim_set_current_win(editor_win)

    -- Left sidebar
    vim.cmd("Neotree show")

    -- Right sidebar: only open the local model when its server is available.
    -- Keep this asynchronous so an offline Ollama does not delay startup.
    vim.system({
        "curl",
        "--silent",
        "--fail",
        "--max-time",
        "1",
        "http://localhost:11434/api/tags",
    }, function(result)
        if result.code ~= 0 then
            return
        end

        vim.schedule(function()
            if not vim.api.nvim_win_is_valid(editor_win) then
                return
            end
            pcall(vim.cmd, "CodeCompanionChat adapter=ollama")
            vim.api.nvim_set_current_win(editor_win)
        end)
    end)

    vim.api.nvim_set_current_win(editor_win)
end

-- Kept as an alias: the blank-slate default UI is just the chrome around an
-- empty buffer.
M.open_default_ui = M.open_chrome

return M
