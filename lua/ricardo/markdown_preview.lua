-- Read-only `glow` rendering of the markdown buffer, toggled with <S-Tab>.
--
-- Why glow rather than an in-buffer renderer: render-markdown.nvim cannot
-- reflow pipe tables to the window width -- it only overlays virtual text on
-- the single physical source line of each row (see
-- render-markdown.nvim/doc/limitations.md), so a table wider than the window
-- gets broken mid-cell by plain line-wrap. `glow` renders markdown fresh at a
-- given width, so tables (and everything else) reflow correctly.
--
-- The cost is that a glow render is a terminal buffer: readable, not editable.
-- So this is a *toggle*, not an automatic view. Markdown files open as
-- ordinary editable text; <S-Tab> swaps the window over to the render, and
-- <S-Tab> (or `q`) swaps it back with the cursor where you left it. The source
-- binding lives in ftplugin/markdown.lua; the one on the render is set here,
-- since the render buffer has no filetype of its own.
--
-- The render is produced from the *buffer* contents via a temp file, not from
-- the file on disk, so unsaved edits and never-written buffers preview fine.
-- No-ops entirely if `glow` isn't on PATH.

local M = {}

local augroup = vim.api.nvim_create_augroup("RicardoGlowPreview", { clear = true })

-- One entry per previewed source buffer. `wo`/`view` are captured when the
-- preview opens and held across re-renders: re-capturing them per render would
-- save the render's own stripped-down settings and lose the real ones.
---@type table<integer, { term_buf: integer, win: integer, wo: table, view: table }>
local previews = {}
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
---@param wo table
local function restore_window(win, wo)
    for opt, value in pairs(wo) do
        vim.wo[win][opt] = value
    end
end

-- Put the source buffer back in the window it was previewed in.
---@param buf integer source buffer
local function close(buf)
    local state = previews[buf]
    previews[buf] = nil
    if not state then
        return
    end
    local timer = resize_timers[buf]
    if timer then
        timer:stop()
        resize_timers[buf] = nil
    end
    if not vim.api.nvim_win_is_valid(state.win) then
        return
    end
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_get_buf(state.win) == state.term_buf then
        vim.api.nvim_win_set_buf(state.win, buf)
        vim.api.nvim_win_call(state.win, function() vim.fn.winrestview(state.view) end)
    end
    -- After the swap, not before: a window keeps a remembered set of
    -- window-local options per buffer, and re-displaying the source buffer
    -- restores its set -- which would undo an earlier restore_window().
    restore_window(state.win, state.wo)
end

-- Render `buf` into a fresh terminal buffer shown in `win`, replacing any
-- previous render there (its bufhidden=wipe collects it on the way out).
---@param win integer
---@param buf integer
---@return integer|nil term_buf
local function render(win, buf)
    if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then
        return nil
    end

    local tmp = vim.fn.tempname() .. ".md"
    local ok = pcall(vim.fn.writefile, vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmp)
    if not ok then
        vim.notify("markdown preview: could not write temp file", vim.log.levels.ERROR)
        return nil
    end

    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.b[term_buf].ricardo_glow_orig_buf = buf

    vim.keymap.set({ "n", "t" }, "<S-Tab>", function() close(buf) end,
        { buffer = term_buf, desc = "Back to markdown source" })
    vim.keymap.set("n", "q", function() close(buf) end,
        { buffer = term_buf, desc = "Back to markdown source" })

    -- A render can also go away without close() -- :bd, :bufdo, a session
    -- reload -- which would leave the window with its gutters stripped.
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        group = augroup,
        buffer = term_buf,
        once = true,
        callback = function()
            local state = previews[buf]
            if state and state.term_buf == term_buf then
                previews[buf] = nil
                if vim.api.nvim_win_is_valid(state.win) then
                    restore_window(state.win, state.wo)
                end
            end
        end,
    })

    -- Claim the state slot *before* the swap: putting the new buffer in the
    -- window wipes the old render synchronously, firing the autocmd above, and
    -- it must not see itself as the current render and tear the preview down.
    if previews[buf] then
        previews[buf].term_buf = term_buf
    end

    vim.api.nvim_win_call(win, function()
        vim.api.nvim_win_set_buf(win, term_buf)

        -- Strip the gutters so glow gets the whole window, and turn off wrap
        -- so a render overshooting by a column is clipped, not reflowed twice.
        -- Done after the swap so these values are remembered against the
        -- render rather than against the source buffer.
        vim.wo[win].number = false
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn = "no"
        vim.wo[win].foldcolumn = "0"
        vim.wo[win].wrap = false

        -- Leave a column of slack: the gutter settings only take effect once
        -- the window redraws, so a same-tick width read can be a column stale.
        local width = math.max(20, vim.api.nvim_win_get_width(win) - 1)

        vim.fn.termopen({ "glow", "-w", tostring(width), "--", tmp }, {
            on_exit = function() os.remove(tmp) end,
        })
    end)
    vim.bo[term_buf].bufhidden = "wipe"

    return term_buf
end

---@param win integer
---@param buf integer
local function open(win, buf)
    if not glow_available() then
        return
    end

    local wo = {
        number = vim.wo[win].number,
        relativenumber = vim.wo[win].relativenumber,
        signcolumn = vim.wo[win].signcolumn,
        foldcolumn = vim.wo[win].foldcolumn,
        wrap = vim.wo[win].wrap,
    }
    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)

    local term_buf = render(win, buf)
    if not term_buf then
        return
    end
    previews[buf] = { term_buf = term_buf, win = win, wo = wo, view = view }
end

-- Swap the current window between the markdown source and its glow render.
function M.toggle()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)

    -- Reached from the render side: the buffer-local <S-Tab> above covers the
    -- usual case, but an explicit :lua ...toggle() can land here too.
    local orig = vim.b[buf].ricardo_glow_orig_buf
    if orig then
        close(orig)
    elseif previews[buf] then
        close(buf)
    else
        open(win, buf)
    end
end

-- Re-render at the new width whenever a window showing a render is resized,
-- debounced so dragging a split doesn't spawn a glow per frame.
---@param buf integer source buffer
local function rerender(buf)
    local state = previews[buf]
    if not state or not vim.api.nvim_win_is_valid(state.win) then
        return
    end
    local existing = resize_timers[buf]
    if existing then
        existing:stop()
    end
    resize_timers[buf] = vim.defer_fn(function()
        resize_timers[buf] = nil
        local st = previews[buf]
        if st and vim.api.nvim_win_is_valid(st.win) then
            render(st.win, buf)
        end
    end, 150)
end

vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
        for _, win in ipairs(vim.v.event.windows) do
            if vim.api.nvim_win_is_valid(win) then
                local orig = vim.b[vim.api.nvim_win_get_buf(win)].ricardo_glow_orig_buf
                if orig then
                    rerender(orig)
                end
            end
        end
    end,
})

vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
        for buf in pairs(previews) do
            rerender(buf)
        end
    end,
})

return M
