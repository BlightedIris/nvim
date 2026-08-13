local M = {}

local function preview_lines(chat)
    if not chat then
        return { "Chat data not available" }
    end

    local lines = { "# " .. (chat.title or "Untitled"), "" }
    for _, message in ipairs(chat.messages or {}) do
        local content = message.content
        if type(content) ~= "string" then
            content = vim.inspect(content)
        end
        vim.list_extend(lines, {
            "## " .. (message.role or "message"),
            "",
        })
        vim.list_extend(lines, vim.split(content, "\n", { plain = true }))
        lines[#lines + 1] = ""
    end
    return lines
end

local function close_open_chats(save_id)
    local Chat = require("codecompanion.interactions.chat")
    for _, entry in ipairs(Chat.buf_get_chat()) do
        local chat = entry.chat
        if chat.opts and chat.opts.save_id == save_id then
            chat:close()
        end
    end
end

function M.delete(save_ids)
    local history = require("codecompanion").extensions.history
    local deleted = 0
    for _, save_id in ipairs(save_ids) do
        close_open_chats(save_id)
        if history.delete_chat(save_id) then
            deleted = deleted + 1
        end
    end
    return deleted
end

function M.open()
    local history = require("codecompanion").extensions.history
    local chats = {}
    for _, chat in pairs(history.get_chats()) do
        chats[#chats + 1] = chat
    end

    if #chats == 0 then
        vim.notify("No saved chats found", vim.log.levels.INFO)
        return
    end

    table.sort(chats, function(a, b)
        return (a.updated_at or 0) > (b.updated_at or 0)
    end)

    require("telescope.pickers").new({}, {
        prompt_title = "Select Chats to Delete (<Tab> select, <Enter> delete)",
        finder = require("telescope.finders").new_table({
            results = chats,
            entry_maker = function(chat)
                local title = chat.title or "Untitled"
                return {
                    value = chat,
                    display = title,
                    ordinal = title,
                }
            end,
        }),
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = require("telescope.previewers").new_buffer_previewer({
            title = "Chat Preview",
            define_preview = function(state, entry)
                vim.bo[state.state.bufnr].filetype = "markdown"
                vim.api.nvim_buf_set_lines(
                    state.state.bufnr,
                    0,
                    -1,
                    false,
                    preview_lines(history.load_chat(entry.value.save_id))
                )
            end,
        }),
        attach_mappings = function(prompt_bufnr)
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")

            actions.select_default:replace(function()
                local picker = action_state.get_current_picker(prompt_bufnr)
                local selected = picker:get_multi_selection()
                if #selected == 0 then
                    local current = action_state.get_selected_entry()
                    selected = current and { current } or {}
                end
                if #selected == 0 then
                    return
                end

                actions.close(prompt_bufnr)
                local count = #selected
                local prompt = count == 1
                    and string.format('Delete chat "%s"?', selected[1].value.title or "Untitled")
                    or string.format("Delete %d chats?", count)
                if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
                    return
                end

                local save_ids = vim.iter(selected):map(function(entry)
                    return entry.value.save_id
                end):totable()
                local deleted = M.delete(save_ids)

                if deleted == count then
                    vim.notify(string.format("Deleted %d saved chat(s)", deleted), vim.log.levels.INFO)
                else
                    vim.notify(
                        string.format("Deleted %d of %d saved chat(s)", deleted, count),
                        vim.log.levels.ERROR
                    )
                end
            end)

            return true
        end,
    }):find()
end

return M
