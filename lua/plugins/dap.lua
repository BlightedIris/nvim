-- Debugging. Three pieces, mirroring the LSP stack:
--   nvim-dap        — the DAP client (the vim.lsp of debuggers)
--   nvim-dap-ui     — panels for scopes/watches/stack/breakpoints (+ nvim-nio dep)
--   mason-nvim-dap  — the mason-lspconfig equivalent: installs
--                     `ensure_installed` adapters and wires each *installed*
--                     one with stock launch configurations via the handlers
--
-- Adapters cover the languages configured in lua/plugins/lsp.lua where a DAP
-- exists: python = debugpy, codelldb = C/C++ (and Rust), bash =
-- bash-debug-adapter. SystemVerilog has no debug adapter (simulators own
-- that space); PowerShell's debugger lives inside powershell-editor-services
-- and has no Mason DAP package.
local dap = require('dap')
local dapui = require('dapui')

require('mason-nvim-dap').setup({
    ensure_installed = { 'python', 'codelldb', 'bash' },
    automatic_installation = true,
    handlers = {
        -- default: stock adapter definition + launch configurations
        function(config)
            require('mason-nvim-dap').default_setup(config)
        end,
        python = function(config)
            -- the stock config only honors $VIRTUAL_ENV; resolve the project
            -- venv the way basedpyright does (lua/ricardo/project.lua) so the
            -- debugger runs the same interpreter the LSP analyzes with
            config.configurations = {
                {
                    type = 'python',
                    request = 'launch',
                    name = 'Python: Launch file',
                    program = '${file}',
                    console = 'integratedTerminal',
                    pythonPath = function()
                        return require('ricardo.project').python(vim.fn.getcwd()) or 'python3'
                    end,
                },
            }
            require('mason-nvim-dap').default_setup(config)
        end,
    },
})

dapui.setup()

-- The panels follow the session: open on launch, close when it ends
dap.listeners.after.event_initialized['dapui'] = function() dapui.open() end
dap.listeners.before.event_terminated['dapui'] = function() dapui.close() end
dap.listeners.before.event_exited['dapui'] = function() dapui.close() end

-- VSCode's debug keys (the benchmark everywhere else in this config)
vim.keymap.set('n', '<F5>', dap.continue, { desc = 'Debug: start/continue' })
vim.keymap.set('n', '<S-F5>', dap.terminate, { desc = 'Debug: stop' })
vim.keymap.set('n', '<F9>', dap.toggle_breakpoint, { desc = 'Debug: toggle breakpoint' })
vim.keymap.set('n', '<F10>', dap.step_over, { desc = 'Debug: step over' })
vim.keymap.set('n', '<F11>', dap.step_into, { desc = 'Debug: step into' })
vim.keymap.set('n', '<S-F11>', dap.step_out, { desc = 'Debug: step out' })
-- Capital B: no clash with the <leader>b* buffer family
vim.keymap.set('n', '<leader>B', function()
    dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))
end, { desc = 'Debug: conditional breakpoint' })
vim.keymap.set('n', '<leader>u', dapui.toggle, { desc = 'Debug: toggle UI panels' })
vim.keymap.set({ 'n', 'v' }, '<leader>e', function() dapui.eval() end,
    { desc = 'Debug: evaluate expression under cursor/selection' })
