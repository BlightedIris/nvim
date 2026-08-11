-- Keep any terminal currently on screen pointed at the same directory as
-- nvim's cwd, so a `:cd`/`:lcd`/`:tcd` doesn't leave terminals behind in the
-- old directory. Only windows visible in the current tabpage are touched --
-- terminal buffers hidden in other splits/tabs are left alone.
vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("RicardoTerminalCwd", { clear = true }),
    callback = function()
        local cwd = vim.v.event.cwd
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.bo[buf].buftype == "terminal" then
                local job_id = vim.b[buf].terminal_job_id
                if job_id then
                    vim.api.nvim_chan_send(job_id, 'cd "' .. cwd .. '"\r')
                end
            end
        end
    end,
})
