require("mason").setup({
    ui = {
        icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗"
        }
    },
    firewall = {
        enabled = true
    }
})

-- Plain tools (not LSPs, so mason-lspconfig's ensure_installed can't cover
-- them). bashls shells out to shellcheck for lint and shfmt for formatting;
-- Mason's bin dir is on PATH for child processes, so installing here is all
-- the wiring they need.
local ensure_tools = { "shellcheck", "shfmt" }
local registry = require("mason-registry")
local missing = vim.tbl_filter(function(name)
    local ok, pkg = pcall(registry.get_package, name)
    return not ok or not pkg:is_installed()
end, ensure_tools)
if #missing > 0 then
    -- refresh first: on a fresh machine the registry isn't downloaded yet
    registry.refresh(function()
        for _, name in ipairs(missing) do
            local ok, pkg = pcall(registry.get_package, name)
            if ok and not pkg:is_installed() then
                pkg:install()
            end
        end
    end)
end
