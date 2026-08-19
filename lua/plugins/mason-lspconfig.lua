-- Bridges mason.nvim <-> nvim-lspconfig.
--
-- `automatic_enable = true` calls `vim.lsp.enable()` for every server that is
-- installed through Mason, so installing a new LSP with `:Mason` is the ONLY
-- action required: no edits to lsp.lua, no restart-specific wiring.
--
-- Must be required AFTER plugins.lsp so that the `vim.lsp.config('*')`
-- capabilities block and any per-server overrides are already registered when
-- the servers get enabled.
require("mason-lspconfig").setup({
    -- Servers that must always exist on any machine this config lands on.
    -- Mason installs them on first startup if they are missing.
    ensure_installed = {
        "lua_ls",
        "basedpyright",
        "bashls",
        "clangd",
        "gopls",
        "rust_analyzer",
    },

    -- Install `ensure_installed` entries automatically on startup.
    automatic_installation = true,

    -- Enable every Mason-installed server automatically.
    -- `exclude` is for servers we start ourselves (e.g. binaries not managed by
    -- Mason, or ones needing bespoke launch logic).
    automatic_enable = {
        exclude = { "verible" },
    },
})
