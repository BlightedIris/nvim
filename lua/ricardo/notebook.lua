-- Notebook plumbing shared by the molten and quarto configs.
--
-- Notebooks are edited as markdown (lua/plugins/jupytext.lua), so a "cell" is
-- a ```python fenced block. Cell navigation and insertion are treesitter
-- queries over that markdown tree rather than a separate cell-marker plugin.
local M = {}

-- Buffers this config treats as notebooks: the ones jupytext converts, plus
-- quarto documents, which are the same markdown-with-code-fences shape. Plain
-- markdown is deliberately excluded -- a README shouldn't pay for an LSP
-- client per code sample, and without otter activated (ftplugin/markdown.lua)
-- the cell runner would have nothing to send.
---@param buf integer?
function M.is_notebook(buf)
    local name = vim.api.nvim_buf_get_name(buf or 0)
    return name:match('%.ipynb$') ~= nil or name:match('%.qmd$') ~= nil
end

-- Ranges of every fenced code block in the buffer, in document order.
-- Rows are 0-indexed: `srow` is the opening ``` line, `erow` the closing one.
local function code_cells(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
    if not ok or not parser then
        return {}
    end
    local tree = parser:parse()[1]
    if not tree then
        return {}
    end

    local query = vim.treesitter.query.parse('markdown', '(fenced_code_block) @cell')
    local cells = {}
    for _, node in query:iter_captures(tree:root(), buf) do
        local srow, _, erow, _ = node:range()
        -- a block ending on a line of its own reports the row *after* the
        -- closing fence; clamp so `erow` is always the closing fence itself
        if erow > srow then
            erow = erow - 1
        end
        table.insert(cells, { srow = srow, erow = erow })
    end
    table.sort(cells, function(a, b) return a.srow < b.srow end)
    return cells
end

M.cells = code_cells

-- The cell containing the cursor, or nil when the cursor is in prose.
function M.current_cell()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    for _, cell in ipairs(code_cells()) do
        if row >= cell.srow and row <= cell.erow then
            return cell
        end
    end
end

-- Jump to the first line *inside* the next/previous cell, so the cursor lands
-- where the quarto runner and molten expect it (VSCode's ctrl-alt-]/[).
---@param dir 1|-1
function M.goto_cell(dir)
    local cells = code_cells()
    if #cells == 0 then
        return
    end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local target
    if dir > 0 then
        for _, cell in ipairs(cells) do
            if cell.srow > row then
                target = cell
                break
            end
        end
    else
        for i = #cells, 1, -1 do
            if cells[i].erow < row then
                target = cells[i]
                break
            end
        end
    end
    if not target then
        return
    end
    -- +2: 0-indexed opening fence -> 1-indexed first content line
    local line = math.min(target.srow + 2, vim.api.nvim_buf_line_count(0))
    vim.api.nvim_win_set_cursor(0, { line, 0 })
end

-- Where a new cell goes: after the cell under the cursor, or after the cursor
-- line when in prose.
local function insert_row(above)
    local cell = M.current_cell()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    if cell then
        return above and cell.srow or cell.erow + 1
    end
    return above and row or row + 1
end

---@param above boolean insert before the current cell instead of after it
function M.insert_code_cell(above)
    local row = insert_row(above)
    local lines = { '', '```python', '', '```', '' }
    vim.api.nvim_buf_set_lines(0, row, row, false, lines)
    -- land on the blank line between the fences, in insert mode
    vim.api.nvim_win_set_cursor(0, { row + 3, 0 })
    vim.cmd.startinsert()
end

-- A markdown cell in jupytext's markdown format is just prose between code
-- fences -- there is no marker to insert, only a blank line to type into.
---@param above boolean
function M.insert_markdown_cell(above)
    local row = insert_row(above)
    vim.api.nvim_buf_set_lines(0, row, row, false, { '', '', '' })
    vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
    vim.cmd.startinsert()
end

--- Saving ------------------------------------------------------------------

-- Set by the wrapped jupytext runner in lua/plugins/jupytext.lua whenever a
-- conversion fails, cleared on success. Holds the CLI's full output.
---@type string?
M.write_error = nil

-- The jupytext markdown format keeps the notebook's metadata in a YAML header
-- at the top of the buffer. It is ordinary editable text sitting where `gg`
-- lands, and nbformat rejects the whole notebook if the kernelspec loses one
-- of its required keys -- a single stray `x` there fails every subsequent :w.
-- Catch that here so the message names the key instead of arriving as a
-- forty-line python traceback.
local KERNELSPEC_KEYS = { 'display_name', 'language', 'name' }

---@param buf integer?
---@return string? error
function M.check_frontmatter(buf)
    local lines = vim.api.nvim_buf_get_lines(buf or 0, 0, 60, false)
    if lines[1] ~= '---' then
        return nil -- no header at all; jupytext is happy to write one
    end

    local start
    for i = 2, #lines do
        if lines[i] == '---' then
            break
        end
        if lines[i]:match('^%s*kernelspec:%s*$') then
            start = i
            break
        end
    end
    if not start then
        return nil -- no kernelspec to get wrong
    end

    local indent = #lines[start]:match('^%s*')
    local seen, strays = {}, {}
    for i = start + 1, #lines do
        local line = lines[i]
        if line == '---' or (line:match('%S') and #line:match('^%s*') <= indent) then
            break
        end
        local key = line:match('^%s*([%w_]+):')
        if key then
            seen[key] = i
            table.insert(strays, key)
        end
    end

    for _, key in ipairs(KERNELSPEC_KEYS) do
        if not seen[key] then
            local near = vim.tbl_filter(function(k)
                return not vim.tbl_contains(KERNELSPEC_KEYS, k)
            end, strays)
            local hint = #near > 0 and (" -- did you mean the '" .. near[1] .. "' on line " .. seen[near[1]] .. '?') or ''
            return ("notebook header: kernelspec (line %d) has no '%s'%s"):format(start, key, hint)
        end
    end
end

--- Kernels -----------------------------------------------------------------

local function available_kernels()
    local ok, kernels = pcall(vim.fn.MoltenAvailableKernels)
    if not ok or type(kernels) ~= 'table' then
        return {}
    end
    return kernels
end

-- Kernel recorded in the .ipynb the buffer came from, if any. The buffer name
-- is still the notebook path -- jupytext swaps the *contents*, not the name.
local function kernel_from_notebook(file)
    local ok, name = pcall(function()
        local handle = assert(io.open(file, 'r'))
        local content = handle:read('a')
        handle:close()
        return vim.json.decode(content).metadata.kernelspec.name
    end)
    return ok and name or nil
end

-- Kernel matching the project venv, following the same venv lookup the LSP
-- and debugger use (lua/ricardo/project.lua). Kernels registered by
-- :NotebookRegisterKernel are named after the venv's parent directory.
local function kernel_from_venv()
    local py = require('ricardo.project').python(vim.fn.getcwd())
    if not py then
        return nil
    end
    -- .../<project>/.venv/bin/python -> <project>
    return vim.fn.fnamemodify(py, ':h:h:h:t')
end

-- Pick a kernel the way VSCode picks an interpreter: the project venv wins,
-- because that's where the notebook's imports actually live.
--
-- The notebook's own kernelspec only wins when it names something specific --
-- a julia or R kernel, or a named venv someone registered. Nearly every
-- python notebook in the wild says "python3", which would otherwise pin every
-- file to the bare interpreter that runs neovim's python host and fail on the
-- first `import pandas`.
function M.resolve_kernel()
    local kernels = available_kernels()
    local function usable(name)
        return name and vim.tbl_contains(kernels, name) and name or nil
    end

    local from_file
    local file = vim.api.nvim_buf_get_name(0)
    if file:match('%.ipynb$') and vim.fn.filereadable(file) == 1 then
        from_file = usable(kernel_from_notebook(file))
    end

    if from_file and from_file ~= 'python3' then
        return from_file
    end
    return usable(kernel_from_venv()) or from_file or usable('python3')
end

-- jupyter_client writes a kernel's connection file into the runtime dir and
-- assumes it exists; on a machine where jupyter has never run it doesn't, and
-- every :MoltenInit fails with a bare ENOENT on that path. Cheaper to create
-- it than to explain the error message.
local function ensure_runtime_dir()
    local data = vim.env.JUPYTER_DATA_DIR
        or vim.fs.joinpath(vim.env.XDG_DATA_HOME or vim.fn.expand('~/.local/share'), 'jupyter')
    vim.fn.mkdir(vim.env.JUPYTER_RUNTIME_DIR or vim.fs.joinpath(data, 'runtime'), 'p')
end

-- Start a kernel for this buffer. Falls back to molten's own picker when no
-- kernel could be resolved, so this key always does something sensible.
function M.init_kernel()
    ensure_runtime_dir()
    local kernel = M.resolve_kernel()
    if kernel then
        vim.cmd(('MoltenInit %s'):format(kernel))
    else
        vim.cmd('MoltenInit')
    end
end

function M.initialized()
    local ok, status = pcall(function() return require('molten.status').initialized() end)
    return ok and status == 'Molten'
end

-- Register the project venv as a jupyter kernel, so notebooks can run against
-- the project's own packages instead of neovim's python host. Idempotent.
function M.register_kernel()
    local py = require('ricardo.project').python(vim.fn.getcwd())
    if not py then
        vim.notify('No project venv found (.venv/venv)', vim.log.levels.WARN)
        return
    end
    local name = vim.fn.fnamemodify(py, ':h:h:h:t')
    vim.notify(('Registering jupyter kernel "%s" from %s'):format(name, py))
    vim.system(
        { py, '-m', 'ipykernel', 'install', '--user', '--name', name, '--display-name', name },
        { text = true },
        function(result)
            vim.schedule(function()
                if result.code == 0 then
                    vim.notify(('Kernel "%s" registered -- run :MoltenInit %s'):format(name, name))
                else
                    vim.notify(
                        'ipykernel install failed:\n' .. (result.stderr or '')
                        .. '\nInstall it first: uv pip install ipykernel',
                        vim.log.levels.ERROR
                    )
                end
            end)
        end
    )
end

-- jupytext can only convert a notebook that already exists, so "new notebook"
-- means writing a minimal valid .ipynb and opening that.
local NOTEBOOK_TEMPLATE = [[
{
 "cells": [],
 "metadata": {
  "kernelspec": { "display_name": "Python 3", "language": "python", "name": "python3" },
  "language_info": {
   "codemirror_mode": { "name": "ipython", "version": 3 },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
]]

function M.new_notebook(name)
    local path = name:match('%.ipynb$') and name or (name .. '.ipynb')
    if vim.fn.filereadable(path) == 1 then
        vim.notify(path .. ' already exists', vim.log.levels.ERROR)
        return
    end
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    local file, err = io.open(path, 'w')
    if not file then
        vim.notify('Could not create ' .. path .. ': ' .. tostring(err), vim.log.levels.ERROR)
        return
    end
    file:write(NOTEBOOK_TEMPLATE)
    file:close()
    vim.cmd.edit(vim.fn.fnameescape(path))
end

vim.api.nvim_create_user_command('NewNotebook', function(opts)
    M.new_notebook(opts.args)
end, { nargs = 1, complete = 'file', desc = 'Create and open a blank jupyter notebook' })

vim.api.nvim_create_user_command('NotebookRegisterKernel', function()
    M.register_kernel()
end, { desc = 'Register the project venv as a jupyter kernel' })

return M
