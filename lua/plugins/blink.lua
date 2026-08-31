-- `setup()` itself resolves the fuzzy matcher: it checks target/release for a
-- locally built library and only falls back to downloading a prebuilt binary if
-- that's missing. The Rust library is built from source here via
-- `cargo build --release` (see README), which also writes target/release/version
-- with the checked-out SHA so blink knows the build is current.
-- Rank completion kinds the way you read an object: data members first,
-- then callables, then types, with noise (keywords/snippets/text) last.
-- Unlisted kinds land between Constructor and Class.
local kinds = require('blink.cmp.types').CompletionItemKind
local kind_priority = {
    [kinds.Field] = 1,
    [kinds.Property] = 1,
    [kinds.EnumMember] = 2,
    [kinds.Variable] = 3,
    [kinds.Constant] = 3,
    [kinds.Value] = 4,
    [kinds.Method] = 5,
    [kinds.Function] = 5,
    [kinds.Constructor] = 6,
    [kinds.Class] = 8,
    [kinds.Interface] = 8,
    [kinds.Struct] = 8,
    [kinds.Enum] = 8,
    [kinds.Module] = 9,
    [kinds.Keyword] = 10,
    [kinds.Snippet] = 11,
    [kinds.Text] = 12,
}
-- Verilog/SystemVerilog reads RTL-first, not object-first: signals and ports
-- above everything, then parameters/enum values, then tasks/functions, then
-- instantiable modules/interfaces and types. Keywords and snippets are the
-- loudest noise from SV servers, so they sink hardest.
local sv_kind_priority = {
    [kinds.Variable] = 1, -- signals, nets
    [kinds.Field] = 1,    -- ports, struct members
    [kinds.Property] = 1,
    [kinds.EnumMember] = 2,
    [kinds.Constant] = 2, -- parameters, localparams
    [kinds.Function] = 3, -- functions, tasks
    [kinds.Method] = 3,
    [kinds.Module] = 4,   -- instantiation targets
    [kinds.Interface] = 4,
    [kinds.Class] = 5,
    [kinds.Struct] = 5,
    [kinds.Enum] = 5,
    [kinds.TypeParameter] = 5,
    [kinds.Keyword] = 8,
    [kinds.Snippet] = 9,
    [kinds.Text] = 10,
}
local function kind_sorter(priority, default)
    return function(a, b)
        local pa = priority[a.kind] or default
        local pb = priority[b.kind] or default
        if pa ~= pb then return pa < pb end
    end
end
local by_kind = kind_sorter(kind_priority, 7)
local by_sv_kind = kind_sorter(sv_kind_priority, 6)

-- public names before `_private` before `__dunder__`; checked before kind so
-- e.g. `__class__` (a Property) still sinks below public methods
local function underscore_tier(label)
    if label:sub(1, 2) == '__' then return 2 end
    if label:sub(1, 1) == '_' then return 1 end
    return 0
end
local function by_visibility(a, b)
    local ta, tb = underscore_tier(a.label), underscore_tier(b.label)
    if ta ~= tb then return ta < tb end
end

-- see the keymap comment below
local function sv_component_docs()
    return require('ricardo.sv_component').show_component_docs({ insert = true })
end

require("blink-cmp").setup({
    fuzzy = {
        implementation = 'rust',
        -- evaluated on every completion pass, so the order adapts:
        sorts = function()
            -- SV: no visibility tiering (`_`-prefixed signals are ordinary
            -- RTL style, not "private"), and the RTL-first kind grouping
            local ft = vim.bo.filetype
            local sv = ft == 'systemverilog' or ft == 'verilog'
            local keyword = require('blink.cmp.completion.trigger.context').get_keyword()
            if #keyword == 0 then
                -- browsing (right after `obj.` or a bare <C-Space>):
                -- strict kind grouping (for Python: public before _private
                -- before __dunder__ first); recency/proximity only orders
                -- within a group
                if sv then return { by_sv_kind, 'score', 'sort_text' } end
                return { by_visibility, by_kind, 'score', 'sort_text' }
            end
            -- typing: match quality rules, visibility/kind only break ties
            -- (typing `_` naturally surfaces underscore names, no demotion)
            if sv then return { 'exact', 'score', by_sv_kind, 'sort_text' } end
            return { 'exact', 'score', by_visibility, by_kind, 'sort_text' }
        end,
    },
    keymap = {
        -- sv_component_docs first: in (System)Verilog, <C-Space> inside a
        -- component instantiation floats the component's header (parameters
        -- + ports) instead of the completion menu — svlangserver has no
        -- signature help for instantiations. It's a no-op (falls through to
        -- 'show') everywhere else, and auto-completion while typing is
        -- unaffected either way.
        ['<C-Space>'] = { sv_component_docs, 'show', 'show_documentation' },
        -- Windows Terminal/ConPTY sends NUL for Ctrl+Space, which Neovim sees as <C-@>
        ['<C-@>']     = { sv_component_docs, 'show', 'show_documentation' },
        ['<Tab>']     = { 'accept', 'fallback' },
    },
    sources = {
        -- buffer is intentionally not listed: blink's built-in
        -- `lsp.fallbacks = { 'buffer' }` kicks in only when the LSP has
        -- nothing to offer, so buffer words never drown out real symbols
        default = { 'lsp', 'path', 'snippets' },
        per_filetype = { codecompanion = { 'codecompanion' } },
        providers = {
            -- keep LSP symbols (properties, methods) above snippets on ties
            snippets = { score_offset = -4 },
            codecompanion = {
                name = 'CodeCompanion',
                module = 'codecompanion.providers.completion.blink',
                score_offset = 100,
            },
        },
    },
    snippets = { preset = 'default' }, -- friendly-snippets is installed
    completion = {
        -- match against the whole word under the cursor, not just the part
        -- before it, and replace all of it on accept — no more word-splitting
        keyword = { range = 'full' },
        menu = { border = 'single' },
        ghost_text = { enabled = true },
        documentation = { auto_show = false, window = { border = 'single' } },
        trigger = { prefetch_on_insert = false },
    },
    signature = { enabled = true },
})
