-- Prefixes a buffer's name in the bufferline with the number of the window
-- it's currently displayed in (if any), matching the window number shown
-- in the winbar/lualine.
local function name_with_winnr(buf)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == buf.bufnr and vim.api.nvim_win_get_config(win).relative == '' then
            return string.format('[%d] %s', vim.api.nvim_win_get_number(win), buf.name)
        end
    end
    return buf.name
end

require('bufferline').setup(
    {
        options = {
            numbers = true,
            name_formatter = name_with_winnr,
        }
    }
)

