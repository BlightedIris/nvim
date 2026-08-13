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

-- Boot layout: neo-tree (left) | editor over terminal (middle) | AI chat (right)
vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("RicardoBootLayout", { clear = true }),
    callback = function()
        -- Don't clobber the layout when opening a specific file (e.g. `nvim foo.lua`)
        if vim.fn.argc() > 0 then
            return
        end

        local shell = vim.fn.has("win32") == 1 and "powershell" or vim.o.shell
        local editor_win = vim.api.nvim_get_current_win()

        -- Middle column: empty editor on top, terminal split below it
        vim.cmd("belowright split")
        vim.cmd.terminal(shell)
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
    end,
})
