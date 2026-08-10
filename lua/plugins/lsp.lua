-- LSP init
vim.lsp.config('verible', {
  cmd = { 'verible-verilog-ls' },
  filetypes = { 'systemverilog', 'verilog' },
})

-- LSP servers below are installed locally into this repo's node_modules via
-- `npm install` (see package.json / package-lock.json), not globally, so
-- their binaries aren't on PATH -- point cmd at the local .bin shims instead.
local npm_bin_dir = vim.fs.joinpath(vim.fn.stdpath('config'), 'node_modules', '.bin')
local function npm_cmd(name, ...)
  local exe = vim.fs.joinpath(npm_bin_dir, name .. (vim.fn.has('win32') == 1 and '.cmd' or ''))
  return { exe, ... }
end

vim.lsp.config('cssls', { cmd = npm_cmd('vscode-css-language-server', '--stdio') })
vim.lsp.config('html', { cmd = npm_cmd('vscode-html-language-server', '--stdio') })
vim.lsp.config('jsonls', { cmd = npm_cmd('vscode-json-language-server', '--stdio') })
vim.lsp.config('dockerls', { cmd = npm_cmd('docker-langserver', '--stdio') })
vim.lsp.config('ts_ls', { cmd = npm_cmd('typescript-language-server', '--stdio') })
vim.lsp.config('yamlls', { cmd = npm_cmd('yaml-language-server', '--stdio') })
vim.lsp.config('sqlls', { cmd = npm_cmd('sql-language-server', 'up', '--method', 'stdio') })
vim.lsp.config('svelte', { cmd = npm_cmd('svelteserver', '--stdio') })
vim.lsp.config('graphql', { cmd = npm_cmd('graphql-lsp', 'server', '-m', 'stream') })

-- vscode-langservers-extracted's markdown server has no built-in nvim-lspconfig
-- entry yet, so it's defined here the same way verible is above.
vim.lsp.config('markdown_ls', {
  cmd = npm_cmd('vscode-markdown-language-server', '--stdio'),
  filetypes = { 'markdown' },
  root_markers = { '.git' },
  init_options = { provideFormatter = true },
})

-- taplo (toml), texlab (latex) and vhdl_ls (vhdl) aren't published on npm --
-- installed instead via `cargo install`, which puts them on PATH in
-- ~/.cargo/bin, so no cmd override is needed for these.

vim.lsp.enable({
    'gopls', 'rust_analyzer', 'clangd', 'basedpyright',
    'lua_ls', 'bashls', 'powershell_es', 'verible',
    -- npm-installed (local to this repo's node_modules)
    'cssls', 'html', 'jsonls', 'dockerls', 'ts_ls', 'yamlls',
    'sqlls', 'svelte', 'graphql', 'markdown_ls',
    -- cargo-installed
    'taplo', 'texlab', 'vhdl_ls',
})
