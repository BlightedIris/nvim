require("ricardo.gui_setup")

-- Terminal:
local shell = vim.fn.has("win32") == 1 and "powershell" or vim.o.shell
print("Shell set to:")
print(shell)
vim.keymap.set("n", "<leader>t", function() vim.cmd.terminal(shell) end)
