-- Applies to EVERY server (current and future), so blink's extra completion
-- capabilities are advertised without per-server wiring.
vim.lsp.config('*', {
  capabilities = require('blink.cmp').get_lsp_capabilities({}, true),
})

-- Python runs two servers with one job each: basedpyright (the engine behind
-- VSCode's Pylance) for completions, hover, rename, references, and type
-- diagnostics; ruff for lint diagnostics and formatting (basedpyright has no
-- formatter, so vim.lsp.buf.format() always resolves to ruff).
-- Venv resolution lives in lua/ricardo/project.lua (shared with the debugpy
-- config in lua/plugins/dap.lua so debugging targets the same interpreter).
local project_python = require('ricardo.project').python

vim.lsp.config('basedpyright', {
  -- With no root markers pyright runs in single-file mode and ignores
  -- workspace settings — including pythonPath — so loose scripts never
  -- resolve their venv. Fall back to the file's directory as the root.
  root_dir = function(bufnr, on_dir)
    local markers =
      { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git' }
    local root = vim.fs.root(bufnr, markers)
      or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
    on_dir(root)
  end,
  before_init = function(_, config)
    local py = project_python(config.root_dir or vim.fn.getcwd())
    if py then
      config.settings = vim.tbl_deep_extend('force', config.settings or {},
        { python = { pythonPath = py } })
    end
  end,
  settings = {
    basedpyright = {
      analysis = {
        -- basedpyright's own default ("recommended") is far stricter than
        -- VSCode; "standard" matches pyright/Pylance defaults
        typeCheckingMode = 'standard',
      },
    },
  },
})

vim.lsp.config('ruff', {
  on_attach = function(client)
    -- keep K on basedpyright's hover; ruff's is noqa-code only
    client.server_capabilities.hoverProvider = false
  end,
})

-- C/C++: clangd is the whole package — completions, clang-format formatting,
-- clang-tidy lint — so no second server is needed. Multi-file projects want a
-- compile_commands.json (or compile_flags.txt) at the root; loose files work
-- out of the box.
vim.lsp.config('clangd', {
  -- background-index persists the project index across restarts; clang-tidy
  -- adds lint diagnostics beyond plain compile errors (the ruff/verilator
  -- role for C++)
  cmd = { 'clangd', '--background-index', '--clang-tidy' },
})
-- A system clangd (e.g. pacman's) isn't Mason-installed, so automatic_enable
-- skips it; enable explicitly whenever *a* clangd is on PATH. Harmlessly
-- redundant once Mason's copy is installed.
if vim.fn.executable('clangd') == 1 then
  vim.lsp.enable('clangd')
end

-- Bash: bashls handles completions/hover and shells out to shellcheck for
-- lint diagnostics; formatting comes from shfmt. Both are plain Mason tools
-- (not LSPs), ensured in lua/plugins/mason.lua since mason-lspconfig only
-- manages language servers.

-- PowerShell: powershell-editor-services bundles PSScriptAnalyzer, so lint,
-- format, and completions all come from the one server. The server itself
-- runs *on* PowerShell, so it can only start where pwsh (or Windows
-- PowerShell) exists — hence the guarded enable below, mirroring verible.
vim.lsp.config('powershell_es', {
  bundle_path = vim.fn.stdpath('data') .. '/mason/packages/powershell-editor-services',
  shell = vim.fn.executable('pwsh') == 1 and 'pwsh' or 'powershell',
})
if vim.fn.executable('pwsh') == 1 or vim.fn.executable('powershell') == 1 then
  vim.lsp.enable('powershell_es')
end

-- SystemVerilog mirrors the Python two-server split: svlangserver (Mason)
-- provides completions and hover — verible-verilog-ls advertises no
-- completionProvider at all — while verible keeps format, lint, and
-- navigation. svlangserver's own linting stays on: it runs verilator, whose
-- compile errors complement verible's style lint.
-- svlangserver's hover/signature gaps on instantiations are papered over by
-- lua/ricardo/sv_component.lua (K and insert-mode <C-Space> float the
-- component type's header instead).
vim.lsp.config('svlangserver', {
  on_attach = function(client)
    -- keep vim.lsp.buf.format() resolving to verible
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end,
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

