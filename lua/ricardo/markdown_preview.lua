-- render-markdown.nvim cannot reflow pipe tables to the window width: it only
-- overlays virtual text on the single physical source line of each row (see
-- render-markdown.nvim/doc/limitations.md), so a table wider than the window
-- gets broken mid-cell by plain line-wrap. `glow` renders markdown fresh at a
-- given width, so tables (and everything else) reflow correctly.
--
-- This swaps the window showing a markdown buffer over to a `glow` render
-- whenever you enter it, and re-renders whenever that window is resized so
-- the reflow stays correct. Press `q` in the preview to go back to editing
-- the real buffer. No-ops entirely if `glow` isn't on PATH.
--
-- Set `vim.g.ricardo_glow_preview = false` to disable this without removing
-- the module.

local augroup = vim.api.nvim_create_augroup("RicardoGlowPreview", { clear = true })

---@type table<integer, { term_buf: integer, win: integer }>
local previews = {}
---@type table<integer, boolean>
local suppress = {}
---@type table<integer, table>
local resize_timers = {}

local warned_missing = false

local function glow_available()
    if vim.fn.executable("glow") == 1 then
        return true
    end
    if not warned_missing then
        warned_missing = true
        vim.notify(
            "glow not found on PATH -- markdown preview disabled (https://github.com/charmbracelet/glow)",
            vim.log.levels.WARN
        )
    end
    return false
end

---@param win integer
---@param buf integer
local function start_glow(win, buf)
    if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
        return
    end
    local file = vim.api.nvim_buf_get_name(buf)
    if file == "" then
        return
    end

    local orig_wo = {
        number = vim.wo[win].number,
        relativenumber = vim.wo[win].relativenumber,
        signcolumn = vim.wo[win].signcolumn,
        foldcolumn = vim.wo[win].foldcolumn,
        wrap = vim.wo[win].wrap,
    }
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].wrap = false

    -- leave a column of slack: gutter settings above only take effect once
    -- the window redraws, so a same-tick width read can be one column stale
    local width = math.max(20, vim.api.nvim_win_get_width(win) - 1)

    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_call(win, function()
        vim.api.nvim_win_set_buf(win, term_buf)
        vim.fn.termopen({ "glow", "-w", tostring(width), "--", file })
    end)
    vim.bo[term_buf].bufhidden = "wipe"
    vim.b[term_buf].ricardo_glow_orig_buf = buf

    previews[buf] = { term_buf = term_buf, win = win }

    vim.keymap.set("n", "q", function()
        suppress[buf] = true
        if vim.api.nvim_win_is_valid(win) then
            vim.wo[win].number = orig_wo.number
            vim.wo[win].relativenumber = orig_wo.relativenumber
            vim.wo[win].signcolumn = orig_wo.signcolumn
            vim.wo[win].foldcolumn = orig_wo.foldcolumn
            vim.wo[win].wrap = orig_wo.wrap
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_win_set_buf(win, buf)
            end
        end
    end, { buffer = term_buf, desc = "Close glow preview, edit markdown source" })

    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        group = augroup,
        buffer = term_buf,
        once = true,
        callback = function()
            if previews[buf] and previews[buf].term_buf == term_buf then
                previews[buf] = nil
            end
        end,
    })
end

---@param buf integer
---@param win integer
local function maybe_preview(buf, win)
    if vim.g.ricardo_glow_preview == false then
        return
    end
    if vim.bo[buf].filetype ~= "markdown" then
        return
    end
    if suppress[buf] then
        suppress[buf] = nil
        return
    end
    if previews[buf] then
        return
    end
    if not glow_available() then
        return
    end
    start_glow(win, buf)
end

-- Deferred via vim.schedule: mutating the window/buffer from inside BufEnter
-- (which can fire mid-:edit, under textlock) is not safe to do synchronously.
vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
        local win = vim.api.nvim_get_current_win()
        vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == args.buf then
                maybe_preview(args.buf, win)
            end
        end)
    end,
})

---@param orig_buf integer
local function restart_preview(orig_buf)
    local state = previews[orig_buf]
    if not state or not vim.api.nvim_win_is_valid(state.win) then
        return
    end
    local existing = resize_timers[orig_buf]
    if existing then
        existing:stop()
        existing:close()
    end
    resize_timers[orig_buf] = vim.defer_fn(function()
        resize_timers[orig_buf] = nil
        local st = previews[orig_buf]
        if st and vim.api.nvim_win_is_valid(st.win) then
            start_glow(st.win, orig_buf)
        end
    end, 150)
end

-- Re-render at the new width whenever a window showing a preview is resized,
-- whether that's an individual window (WinResized) or the whole UI (VimResized).
vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
        for _, win in ipairs(vim.v.event.windows) do
            if vim.api.nvim_win_is_valid(win) then
                local buf = vim.api.nvim_win_get_buf(win)
                local orig = vim.b[buf].ricardo_glow_orig_buf
                if orig then
                    restart_preview(orig)
                end
            end
        end
    end,
})

vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
        for orig in pairs(previews) do
            restart_preview(orig)
        end
    end,
})
