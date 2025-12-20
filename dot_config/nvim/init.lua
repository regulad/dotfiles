-- Plugin
require("config.lazy")

-- Map Treesitter highlight groups to traditional Vim syntax groups
vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "*",
    callback = function()
        -- Link Treesitter groups to standard Vim syntax groups
        local links = {
            ['@variable'] = 'Identifier',
            ['@function'] = 'Function',
            ['@function.call'] = 'Function',
            ['@keyword'] = 'Keyword',
            ['@keyword.function'] = 'Keyword',
            ['@string'] = 'String',
            ['@number'] = 'Number',
            ['@boolean'] = 'Boolean',
            ['@comment'] = 'Comment',
            ['@type'] = 'Type',
            ['@constant'] = 'Constant',
            ['@operator'] = 'Operator',
            ['@punctuation.bracket'] = 'Delimiter',
            ['@punctuation.delimiter'] = 'Delimiter'
        }

        for treesitter_group, vim_group in pairs(links) do
            vim.api.nvim_set_hl(0, treesitter_group, {link = vim_group})
        end
    end
})

-- LSP
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md
-- pnpm i -g pyright
vim.lsp.enable('pyright')
-- brew install JetBrains/utils/kotlin-lsp
vim.lsp.enable('kotlin_lsp')
-- pnpm install -g typescript typescript-language-server
vim.lsp.enable('ts_ls')
-- rustup component add rust-src
vim.lsp.enable('rust_analyzer')

-- Legacy
vim.cmd('source ' .. vim.fn.stdpath('config') .. '/legacy.vim')
