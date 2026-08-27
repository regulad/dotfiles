" clipboard.vim - system clipboard for Vim builds compiled without +clipboard
"
" Homebrew's Vim (and other minimal builds) ship -clipboard, -wayland_clipboard
" and -xterm_clipboard.  On such a build Vim resolves v:clipmethod to "none" at
" startup and then silently discards 'clipboard', so the
" `set clipboard^=unnamedplus` in ~/.vimrc never survives.  Vim 9.2 can instead
" delegate the "+"/"*" registers to a script provider, so register one that
" shells out to the same tools the Neovim config uses (~/.config/nvim/init.lua),
" falling back to OSC 52 when the session owns no clipboard (ssh, bare tty).
"
" The provider is *appended* to 'clipmethod', so builds that do have a working
" native clipboard keep using it and only fall through to this.
"
" Runs as a plugin rather than from ~/.vimrc because 'clipboard' is cleared
" after the vimrc is sourced; re-asserting it here is what makes it stick.

" Neovim gets ~/.vim on its runtimepath via ~/.config/nvim/legacy.vim, but it
" configures the clipboard itself through vim.g.clipboard.
if has('nvim') || !has('clipboard_provider')
    finish
endif

if exists('g:loaded_clipboard_provider')
    finish
endif
let g:loaded_clipboard_provider = 1

" 'cpoptions' can still carry "C" here, which turns the \ continuations below
" into commands.  Restored at the bottom of the file.
let s:save_cpo = &cpoptions
set cpoptions&vim

function! s:CopyCmd() abort
    if has('mac')
        return ['pbcopy']
    elseif has('wsl')
        return ['clip.exe']
    elseif has('win32')
        return executable('win32yank') ? ['win32yank', '-i', '--crlf'] : []
    elseif !empty($PREFIX) && executable('termux-clipboard-set')
        " PREFIX is set by Termux
        return ['termux-clipboard-set']
    elseif !empty($WAYLAND_DISPLAY)
        return executable('wl-copy') ? ['wl-copy', '--type', 'text/plain'] : []
    elseif !empty($DISPLAY)
        if executable('xclip')
            return ['xclip', '-selection', 'clipboard', '-i']
        elseif executable('xsel')
            return ['xsel', '--clipboard', '--input']
        endif
    endif
    return []
endfunction

function! s:PasteCmd() abort
    if has('mac')
        return ['pbpaste']
    elseif has('wsl')
        return ['/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe',
              \ '-NoLogo', '-NoProfile', '-c',
              \ '[Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))']
    elseif has('win32')
        return executable('win32yank') ? ['win32yank', '-o', '--lf'] : []
    elseif !empty($TMUX)
        return ['tmux', 'save-buffer', '-']
    elseif !empty($PREFIX) && executable('termux-clipboard-get')
        return ['termux-clipboard-get']
    elseif !empty($WAYLAND_DISPLAY)
        return executable('wl-paste') ? ['wl-paste', '--no-newline'] : []
    elseif !empty($DISPLAY)
        if executable('xclip')
            return ['xclip', '-selection', 'clipboard', '-o']
        elseif executable('xsel')
            return ['xsel', '--clipboard', '--output']
        endif
    endif
    return []
endfunction

let s:copy_cmd = s:CopyCmd()
let s:paste_cmd = s:PasteCmd()

" Text kept locally so that a copy is readable back even when there is nothing
" to paste from (OSC 52 is write-only in practice; terminals rarely answer the
" query, and answering it is a security hazard anyway).
let s:last_copy = {'type': 'v', 'lines': []}

function! s:Copy(reg, type, lines) abort
    " Linewise and blockwise registers carry a trailing line break.
    let l:text = join(a:lines, "\n") . (a:type ==# 'v' ? '' : "\n")
    let s:last_copy = {'type': a:type, 'lines': copy(a:lines)}

    if !empty(s:copy_cmd)
        call system(s:copy_cmd, l:text)
        if v:shell_error == 0
            return
        endif
    endif

    " OSC 52; tmux forwards this itself given `set -s set-clipboard on`.
    call echoraw("\<Esc>]52;c;" . base64_encode(str2blob([l:text])) . "\<C-g>")
endfunction

function! s:Paste(reg) abort
    if !empty(s:paste_cmd)
        let l:out = system(s:paste_cmd)
        if v:shell_error == 0
            " An empty type lets Vim pick; a trailing newline means linewise.
            let l:type = l:out =~# "\n$" ? 'V' : 'v'
            return [l:type, split(substitute(l:out, "\n$", '', ''), "\n", 1)]
        endif
    endif
    return [s:last_copy.type, s:last_copy.lines]
endfunction

let v:clipproviders['shellout'] = {
    \ 'available': {-> v:true},
    \ 'copy': {
    \     '+': function('s:Copy'),
    \     '*': function('s:Copy'),
    \ },
    \ 'paste': {
    \     '+': function('s:Paste'),
    \     '*': function('s:Paste'),
    \ },
    \ }

set clipmethod+=shellout
set clipboard^=unnamedplus

let &cpoptions = s:save_cpo
unlet s:save_cpo
