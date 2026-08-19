-- Session management. Sessions are stored under stdpath('data')/sessions,
-- which is created on demand so the first write doesn't fail.
local sessions_dir = vim.fn.stdpath('data') .. '/sessions'
vim.fn.mkdir(sessions_dir, 'p')

local sessions = require('mini.sessions')

sessions.setup({
    -- Don't touch sessions on start/exit; writing/reading is explicit below
    autoread = false,
    autowrite = true,
    directory = sessions_dir,
})

vim.keymap.set('n', '<leader>ss', function() sessions.select('write') end,
    { noremap = true, desc = 'Write/overwrite a session' })
vim.keymap.set('n', '<leader>sl', function() sessions.select('read') end,
    { noremap = true, desc = 'Load a session' })
vim.keymap.set('n', '<leader>sx', function() sessions.select('delete') end,
    { noremap = true, desc = 'Delete a session' })
