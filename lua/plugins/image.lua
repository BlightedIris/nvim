-- Inline images in the terminal, via the Kitty graphics protocol. Ghostty
-- (this config's terminal) implements that protocol, so the `kitty` backend
-- works as-is -- no ueberzug fallback needed.
--
-- Two consumers: markdown buffers (image links render in place, like VSCode's
-- markdown preview) and molten-nvim, which hands plot/figure output here to
-- draw it under the code cell (lua/plugins/molten.lua sets the provider).
--
-- Requires ImageMagick on PATH for the `magick_cli` processor -- without it
-- images silently fail to draw while text output keeps working.
require('image').setup({
    backend = 'kitty',
    processor = 'magick_cli',

    integrations = {
        markdown = {
            enabled = true,
            -- notebooks are markdown (see lua/plugins/jupytext.lua), and
            -- quarto buffers share the same syntax
            filetypes = { 'markdown', 'quarto' },
            -- redrawing every keystroke in insert mode flickers badly; the
            -- image reappears the moment you leave insert
            clear_in_insert_mode = false,
            download_remote_images = true,
        },
        -- everything else off: these are formats this config never edits, and
        -- each enabled integration parses every buffer of its filetype
        asciidoc = { enabled = false },
        typst = { enabled = false },
        neorg = { enabled = false },
        syslang = { enabled = false },
    },

    -- Defaults cap images at half the window height, which crops matplotlib
    -- output that molten draws as virtual text; 100% lets a plot use the
    -- whole window and still bounds it to something finite.
    --
    -- Do NOT use math.huge here, which is what most molten guides suggest:
    -- an unbounded cap makes the geometry maths produce an infinite height,
    -- and neovim then spins at 100% CPU, unkillable from inside, the moment
    -- molten renders a plot. Molten's own virt_text_max_lines is the real
    -- limit on how tall inline output gets anyway.
    max_width_window_percentage = 100,
    max_height_window_percentage = 100,

    -- Images live above the terminal grid, so a float (completion menu,
    -- diagnostic popup, molten's output window) drawn on top of one leaves
    -- the pixels visible unless we clear them.
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = {
        'cmp_menu',
        'cmp_docs',
        'scrollview',
        'scrollview_sign',
        -- molten's output buffers have no filetype; without this entry every
        -- image molten draws would immediately clear itself
        '',
    },

    -- Opening a .png from neo-tree renders it instead of showing binary junk
    hijack_file_patterns = { '*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.avif' },
})
