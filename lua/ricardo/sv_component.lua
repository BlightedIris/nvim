-- Component docs for (System)Verilog instantiations.
--
-- svlangserver's hover is position-sensitive to the point of being useless on
-- an instantiation: the type name returns nothing, `.PARAM`/`.port` return
-- nothing, and the instance name echoes the whole instantiation back. It also
-- has no signature help for module parameter/port lists (only for
-- functions/tasks), so there is no built-in "what do I pass here?".
--
-- This module answers both wants with one primitive: anywhere inside an
-- instantiation, find the component *type*, resolve its declaration (verible's
-- definition works where svlangserver's doesn't; svlangserver's workspace
-- symbol index is the cross-file fallback), and float the module header —
-- doc comments, parameters, and ports.
--
-- Wired up as: normal-mode `K` inside an instantiation (falls back to plain
-- hover elsewhere, see the FileType autocmd below) and insert-mode <C-Space>
-- (see lua/plugins/blink.lua).
local M = {}

local sv_fts = { systemverilog = true, verilog = true }

-- Words that start a statement but can never be a component type in the
-- `type #(` / `type instance (` header shapes the fallback scanner matches.
local sv_keywords = {}
for w in ([[module macromodule interface program primitive task function
    if else for while foreach repeat case casex casez always always_comb
    always_ff always_latch initial final assign return typedef genvar
    generate input output inout logic wire reg bit int integer localparam
    parameter begin end fork join wait disable]]):gmatch('%S+') do
    sv_keywords[w] = true
end

-- Fallback for an instantiation that is still being typed: with an unclosed
-- `(` there is no *_instantiation node in the tree yet, so scan upward from
-- the cursor for a header start instead. Only the name has to be right —
-- resolution falls back to svlangserver's symbol index, which is built from
-- the last good parse and doesn't care that the buffer is mid-edit.
local function typed_instantiation(bufnr)
    local row = vim.api.nvim_win_get_cursor(0)[1] -- 1-based
    local first = math.max(1, row - 20)
    local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, row, false)
    for i = #lines, 1, -1 do
        local line = lines[i]
        -- `type #(` — the `#(` is unambiguous
        local pos, name = line:match('()([%a_][%w_]*)%s*#%s*%(')
        if not pos then
            -- `type instance (` — two identifiers then a paren
            pos, name = line:match('^%s*()([%a_][%w_]*)%s+[%a_][%w_]*%s*%(')
        end
        if pos and not sv_keywords[name] then
            return { first + i - 2, pos - 1 }, name -- 0-based row/col
        end
        -- a `;` above the cursor line ends the statement being typed
        if i < #lines and line:find(';') then return end
    end
end

-- The type name is the first simple_identifier child of the enclosing
-- *_instantiation node (module_instantiation, interface_instantiation, ...).
local function instantiation_type(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then return end
    parser:parse()
    local node = vim.treesitter.get_node({ bufnr = bufnr })
    while node and not node:type():find('_instantiation$') do
        node = node:parent()
    end
    if not node then return typed_instantiation(bufnr) end
    for child in node:iter_children() do
        if child:type() == 'simple_identifier' then
            local row, col = child:range()
            return { row, col }, vim.treesitter.get_node_text(child, bufnr)
        end
    end
end

-- Module header: any `//` doc block directly above the declaration, then the
-- declaration itself through the first `;` outside parentheses (covers both
-- `module m #(...) (...);` and portless `module m;`).
local function header_lines(fname, lnum) -- lnum is 0-based
    local bufnr = vim.fn.bufnr(fname)
    local lines
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    else
        lines = vim.fn.readfile(fname)
    end
    local start = lnum + 1
    local doc_from = start
    while doc_from > 1 and lines[doc_from - 1]:match('^%s*//') do
        doc_from = doc_from - 1
    end
    local out = {}
    for i = doc_from, start - 1 do
        out[#out + 1] = lines[i]
    end
    local depth = 0
    for i = start, math.min(start + 100, #lines) do
        local line = lines[i]
        out[#out + 1] = line
        for ch in line:gmatch('[();]') do
            if ch == '(' then
                depth = depth + 1
            elseif ch == ')' then
                depth = depth - 1
            elseif depth <= 0 then -- ';' outside parens: header complete
                return out
            end
        end
    end
    return out
end

-- Definition at the type-name position, first server that answers wins
-- (verible in practice); svlangserver's workspace/symbol index covers the
-- cases definition misses. cb(fname, lnum) or cb(nil).
local function resolve_declaration(bufnr, pos, name, cb)
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = pos[1], character = pos[2] },
    }
    vim.lsp.buf_request_all(bufnr, 'textDocument/definition', params, function(results)
        for _, res in pairs(results) do
            local result = res.result
            if result and result ~= vim.NIL then
                local loc = result[1] or result
                local uri = loc.uri or loc.targetUri
                local range = loc.range or loc.targetSelectionRange
                if uri and range then
                    return cb(vim.uri_to_fname(uri), range.start.line)
                end
            end
        end
        local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'svlangserver' })[1]
        if not client then return cb(nil) end
        client:request('workspace/symbol', { query = name }, function(_, symbols)
            for _, sym in ipairs(symbols or {}) do
                if sym.name == name and sym.location then
                    return cb(vim.uri_to_fname(sym.location.uri), sym.location.range.start.line)
                end
            end
            cb(nil)
        end, bufnr)
    end)
end

--- Float the docs of the component type whose instantiation the cursor is in.
--- Returns false (without side effects) when the cursor isn't inside an
--- instantiation, so callers can fall back to their default behavior.
--- opts.insert keeps the float up while typing (it closes on InsertLeave
--- instead of CursorMoved) and suppresses the hover fallback.
function M.show_component_docs(opts)
    opts = opts or {}
    local bufnr = vim.api.nvim_get_current_buf()
    if not sv_fts[vim.bo[bufnr].filetype] then return false end
    local pos, name = instantiation_type(bufnr)
    if not pos then return false end
    resolve_declaration(bufnr, pos, name, function(fname, lnum)
        if not fname then
            if not opts.insert then vim.lsp.buf.hover() end
            return
        end
        vim.schedule(function()
            vim.lsp.util.open_floating_preview(header_lines(fname, lnum), 'systemverilog', {
                border = 'single',
                max_width = 80,
                focus_id = 'sv-component-docs', -- press again to focus/scroll
                close_events = opts.insert and { 'InsertLeave', 'BufLeave' }
                    or { 'CursorMoved', 'InsertEnter', 'BufLeave' },
            })
        end)
    end)
    return true
end

-- K: component docs inside an instantiation, plain LSP hover elsewhere.
vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'systemverilog', 'verilog' },
    callback = function(args)
        vim.keymap.set('n', 'K', function()
            if not M.show_component_docs() then
                vim.lsp.buf.hover()
            end
        end, { buffer = args.buf, desc = 'Hover (component docs in instantiations)' })
    end,
})

return M
