-- Terminal output for the installer.
--
-- `nvim -l` gives us a plain stdio process, so everything here is io.write
-- rather than :echo -- vim.notify and friends need a UI that headless mode
-- does not have.
local M = {}

local color_enabled = not (os.getenv('NO_COLOR') or os.getenv('CI'))

local codes = {
    reset = '\27[0m',
    bold = '\27[1m',
    dim = '\27[2m',
    red = '\27[31m',
    green = '\27[32m',
    yellow = '\27[33m',
    blue = '\27[34m',
    cyan = '\27[36m',
}

local function paint(color, text)
    if not color_enabled then
        return text
    end
    return (codes[color] or '') .. text .. codes.reset
end

M.paint = paint

function M.set_color(enabled)
    color_enabled = enabled
end

local function emit(text)
    io.write(text, '\n')
    io.stdout:flush()
end

-- A numbered phase banner: the four stages the run moves through.
function M.banner(text)
    emit('')
    emit(paint('bold', '── ' .. text .. ' ') .. paint('dim', string.rep('─', math.max(0, 60 - #text))))
end

function M.step(text)
    emit(paint('cyan', '▶ ') .. text)
end

function M.ok(text)
    emit(paint('green', '  ✓ ') .. text)
end

function M.skip(text)
    emit(paint('dim', '  · ') .. paint('dim', text))
end

function M.warn(text)
    emit(paint('yellow', '  ! ') .. text)
end

function M.err(text)
    emit(paint('red', '  ✗ ') .. text)
end

function M.info(text)
    emit('  ' .. text)
end

function M.dim(text)
    emit(paint('dim', '  ' .. text))
end

function M.plain(text)
    emit(text)
end

-- Ask a yes/no question. Returns `default` when stdin is not interactive
-- (piped installs, CI) so the run never blocks on a closed stdin.
---@param question string
---@param default boolean
---@return boolean
function M.confirm(question, default)
    local suffix = default and ' [Y/n] ' or ' [y/N] '
    io.write(paint('yellow', '? ') .. question .. suffix)
    io.stdout:flush()
    local answer = io.read('l')
    if answer == nil then
        emit(default and 'y' or 'n')
        return default
    end
    answer = answer:lower():gsub('%s', '')
    if answer == '' then
        return default
    end
    return answer:sub(1, 1) == 'y'
end

return M
