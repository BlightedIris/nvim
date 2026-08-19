-- Delete/wipeout buffers while preserving the window layout.
local bufremove = require('mini.bufremove')

bufremove.setup()

vim.keymap.set('n', '<leader>bd', function() bufremove.delete() end,
    { noremap = true, desc = 'Delete buffer, keep window layout' })
vim.keymap.set('n', '<leader>bD', function() bufremove.delete(0, true) end,
    { noremap = true, desc = 'Force delete buffer (discard changes)' })
