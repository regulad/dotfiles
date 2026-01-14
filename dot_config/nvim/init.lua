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

if vim.g.vscode then
    -- Neovim in VSCode extension

    local vscode = require('vscode')
    vim.notify = vscode.notify
else
    -- ordinary Neovim

    -- LSP
    -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md
    vim.lsp.enable('jdtls')
    vim.lsp.enable('pyright')
    vim.lsp.enable('kotlin_lsp')
    vim.lsp.enable('ts_ls')
    vim.lsp.enable('rust_analyzer')
    vim.lsp.enable('bashls')
    require('lspconfig').harper_ls.setup {}
    

    -- statuscol bug; will not update statuscol on each cursor move
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        -- double underscore on the redraw method because it is "experimental" (even after being included in 2 major releases without regressions)
        callback = function() vim.api.nvim__redraw({statuscolumn = true}) end
    })
end


-- Legacy
vim.cmd('source ' .. vim.fn.stdpath('config') .. '/legacy.vim')
