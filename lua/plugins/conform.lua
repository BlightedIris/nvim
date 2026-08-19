-- Single, editor-agnostic formatting entry point.
--
-- `<C-s>` (see lua/ricardo/remaps.lua) calls conform.format(). Conform picks
-- the formatter for the current filetype from the table below; if none is
-- configured or installed it falls back to the attached LSP's formatter.
-- Installing a formatter via `:Mason` is therefore the only action needed --
-- add its name here once and every buffer of that filetype uses it.
local conform = require("conform")

conform.setup({
    formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format", "black", stop_after_first = true },
        go = { "goimports", "gofmt" },
        rust = { "rustfmt" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        json = { "prettierd", "prettier", stop_after_first = true },
        jsonc = { "prettierd", "prettier", stop_after_first = true },
        yaml = { "prettierd", "prettier", stop_after_first = true },
        markdown = { "prettierd", "prettier", stop_after_first = true },
        javascript = { "prettierd", "prettier", stop_after_first = true },
        typescript = { "prettierd", "prettier", stop_after_first = true },

        -- Applies to every filetype not listed above: trim trailing
        -- whitespace/newlines so the keymap always does *something*.
        ["_"] = { "trim_whitespace" },
    },

    -- Formatters installed by Mason live in a data dir that is not on PATH by
    -- default; make conform look there too.
    formatters = {},

    -- Do not format on save: formatting stays an explicit <C-s> action.
    format_on_save = nil,

    notify_on_error = true,
})

-- Make Mason's bin directory visible to conform's formatter lookup so a
-- freshly `:MasonInstall`-ed formatter is found without a restart.
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
if vim.fn.isdirectory(mason_bin) == 1 and not vim.env.PATH:find(mason_bin, 1, true) then
    vim.env.PATH = mason_bin .. (vim.fn.has("win32") == 1 and ";" or ":") .. vim.env.PATH
end

-- `:Format` for parity with the keymap.
vim.api.nvim_create_user_command("Format", function(args)
    local range = nil
    if args.count ~= -1 then
        local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
        range = {
            start = { args.line1, 0 },
            ["end"] = { args.line2, end_line:len() },
        }
    end
    conform.format({ async = true, lsp_format = "fallback", range = range })
end, { range = true })
