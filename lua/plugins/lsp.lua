-- Applies to EVERY server (current and future), so blink's extra completion
-- capabilities are advertised without per-server wiring.
vim.lsp.config('*', {
  capabilities = require('blink.cmp').get_lsp_capabilities({}, true),
})

-- Only servers that Mason does NOT manage need explicit config/enable here.
-- Everything installed via `:Mason` is enabled automatically by
-- lua/plugins/mason-lspconfig.lua.
vim.lsp.config('verible', {
  cmd = { 'verible-verilog-ls' },
  filetypes = { 'systemverilog', 'verilog' },
})

if vim.fn.executable('verible-verilog-ls') == 1 then
  vim.lsp.enable('verible')
end

