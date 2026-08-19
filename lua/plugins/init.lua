require('plenary')

require("plugins.window-picker")
require("plugins.mason")
require("plugins.blink")
require("plugins.lsp")
-- after plugins.lsp: capabilities/overrides must be registered before servers
-- are auto-enabled
require("plugins.mason-lspconfig")
require("plugins.conform")
require("plugins.lualine")
require("plugins.neo-tree")
require("plugins.telescope")
require("plugins.todo-comments")
require("plugins.codecompanion")
require("plugins.treesitter")
require("plugins.render-markdown")

-- mini.nvim modules
require("plugins.mini-ai")
require("plugins.mini-align")
require("plugins.mini-bracketed")
require("plugins.mini-bufremove")
require("plugins.mini-sessions")
require("plugins.mini-splitjoin")
require("plugins.mini-surround")
