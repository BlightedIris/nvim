require("nvim-treesitter").setup {
  ensure_installed = {
    'bash',
    'c',
    'cpp',
    'css',
    'diff',
    'dockerfile',
    'git_config',
    'git_rebase',
    'gitattributes',
    'gitcommit',
    'gitignore',
    'go',
    'goctl',
    'gomod',
    'gosum',
    'gotmpl',
    'gowork',
    'graphql',
    'html',
    'htmldjango',
    'http',
    'javascript',
    'jinja',
    'jinja_inline',
    'json',
    'jsx',
    'latex',
    'ledger',
    'llvm',
    'lua',
    'luadoc',
    'make',
    'markdown',
    'markdown_inline',
    'mermaid',
    'powershell',
    'python',
    'regex',
    'rust',
    'sql',
    'ssh_config',
    'svelte',
    'systemverilog',
    'tcl',
    'toml',
    'typescript',
    'vhdl',
    'yaml',
    'zig',
}
}
local opt = vim.opt

opt.foldmethod = "expr"
-- nvim_treesitter#foldexpr() belonged to the old nvim-treesitter plugin's
-- Vimscript compat layer, which the main-branch rewrite (installed here)
-- doesn't ship -- foldexpr was silently failing on every line. Neovim's
-- built-in vim.treesitter.foldexpr() is the replacement.
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
-- Vim's own default foldlevel is 0 (everything closed) when unset -- that,
-- not the broken foldexpr above, is why files opened fully collapsed.
opt.foldlevel = 99
opt.foldlevelstart = 99
