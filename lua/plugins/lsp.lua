-- LSP init
vim.lsp.config('verible', {
  cmd = { 'verible-verilog-ls' },
  filetypes = { 'systemverilog', 'verilog' },
})

vim.lsp.enable({
  'gopls', 'rust_analyzer', 'clangd', 'basedpyright',
  'lua_ls', 'bashls', 'powershell_es', 'verible',
})


