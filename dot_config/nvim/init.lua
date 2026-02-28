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
    vim.lsp.enable('kotlin_lsp')
    vim.lsp.enable('ts_ls')
    vim.lsp.enable('ty')
    vim.lsp.enable('ruff')
    vim.lsp.enable('rust_analyzer')
    vim.lsp.enable('bashls')
    vim.lsp.enable('harper_ls')
    vim.lsp.enable('yamlls')
    vim.lsp.enable('ruby_lsp')

    -- statuscol bug; will not update statuscol on each cursor move
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        -- double underscore on the redraw method because it is "experimental" (even after being included in 2 major releases without regressions)
        callback = function() vim.api.nvim__redraw({statuscolumn = true}) end
    })

    vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*",
        callback = function() vim.lsp.buf.format({async = false}) end
    })
end

-- Legacy
vim.cmd('source ' .. vim.fn.stdpath('config') .. '/legacy.vim')

-- osc52 copying & native pasting
-- written by Sonnet 4.6, checked by PW
local function get_paste_cmd()
  if vim.fn.has("mac") == 1 then
    return { "pbpaste" }

  elseif vim.fn.has("wsl") == 1 then
    return {
      "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", 
      "-NoLogo", "-NoProfile", "-c",
      "[Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace(\"`r\", \"\"))",
    }

  elseif vim.fn.has("win32") == 1 then
    if vim.fn.executable("win32yank") == 1 then
      return { "win32yank", "-o", "--lf" }
    end

  elseif vim.env.TMUX ~= nil then
    return { "tmux", "save-buffer", "-" }

  elseif vim.env.PREFIX ~= nil and vim.fn.executable("termux-clipboard-get") == 1 then
    -- PREFIX is set by Termux
    return { "termux-clipboard-get" }

  elseif vim.env.WAYLAND_DISPLAY ~= nil then
    if vim.fn.executable("wl-paste") == 1 then
      return { "wl-paste", "--no-newline" }
    elseif vim.fn.executable("waypaste") == 1 then
      return { "waypaste", "-t", "text/plain" }
    end

  elseif vim.env.DISPLAY ~= nil then
    if vim.fn.executable("xclip") == 1 then
      return { "xclip", "-selection", "clipboard", "-o" }
    elseif vim.fn.executable("xsel") == 1 then
      return { "xsel", "--clipboard", "--output" }
    end
  end

  return nil
end

local function get_copy_cmd()
  --if vim.env.TMUX ~= nil then
  --  return { "tmux", "load-buffer", "-" }

  --else
  if vim.env.PREFIX ~= nil and vim.fn.executable("termux-clipboard-set") == 1 then
    return { "termux-clipboard-set" }
  end

  return nil
end

local osc52 = require("vim.ui.clipboard.osc52")
local copy_cmd = get_copy_cmd()
local paste_cmd = get_paste_cmd()

local function make_copy(reg)
  if copy_cmd then
    return copy_cmd
  end
  return osc52.copy(reg)
end

local function native_paste(_)
  if paste_cmd == nil then
    return { vim.fn.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
  end
  local ok, result = pcall(vim.fn.systemlist, paste_cmd)
  if ok and vim.v.shell_error == 0 then
    return { result, "v" }
  end
  return { vim.fn.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
end

vim.g.clipboard = {
  name = "osc52-copy-native-paste",
  copy = {
    ["+"] = make_copy("+"),
    ["*"] = make_copy("*"),
  },
  paste = {
    ["+"] = native_paste,
    ["*"] = native_paste,
  },
}

vim.o.clipboard = "unnamedplus"
