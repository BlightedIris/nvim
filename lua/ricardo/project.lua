-- Project-level lookups shared by the LSP and DAP configs.
local M = {}

-- VSCode auto-selects the workspace interpreter; pyright/debugpy by
-- themselves only use `python` from PATH, so packages living in an
-- unactivated project venv resolve to Unknown. Mirror VSCode: prefer an
-- activated venv, else find .venv/venv upward from root.
function M.python(root)
    local bin = vim.fn.has('win32') == 1 and 'Scripts/python.exe' or 'bin/python'
    if vim.env.VIRTUAL_ENV then
        local py = vim.fs.joinpath(vim.env.VIRTUAL_ENV, bin)
        if vim.fn.executable(py) == 1 then return py end
    end
    for _, name in ipairs({ '.venv', 'venv' }) do
        local found = vim.fs.find(name, { path = root, upward = true, type = 'directory' })[1]
        if found then
            local py = vim.fs.joinpath(found, bin)
            if vim.fn.executable(py) == 1 then return py end
        end
    end
end

return M
