-- LSP init
vim.lsp.config('verible', {
  cmd = { 'verible-verilog-ls' },
  filetypes = { 'systemverilog', 'verilog' },
})

-- powershell_es ships as a module bundle, not a standalone binary on PATH --
-- see tools/binaries.toml / tools/install-binaries.ps1, which extract it here.
vim.lsp.config('powershell_es', {
  bundle_path = vim.fn.expand('~/bin/powershell_es'),
})

vim.lsp.enable({
    'gopls', 'rust_analyzer', 'clangd', 'basedpyright',
    'lua_ls', 'bashls', 'powershell_es', 'verible',
})
