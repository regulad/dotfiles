" legacy.vim - Source traditional Vim configuration in Neovim
" This file bridges traditional Vim config into Neovim

" Source system-wide vimrc if it exists
if filereadable('/etc/vim/vimrc')
    source /etc/vim/vimrc
endif

" Source user's vimrc if it exists
if filereadable(expand('~/.vimrc'))
    source ~/.vimrc
endif

" Add ~/.vim to runtimepath if not already present
" This allows Neovim to find plugin, after, ftplugin, etc. directories
if !empty(glob('~/.vim'))
    set runtimepath^=~/.vim
    set runtimepath+=~/.vim/after
endif

" Note: With ~/.vim in runtimepath, Neovim will automatically load:
" - ~/.vim/plugin/*.vim (plugins)
" - ~/.vim/after/plugin/*.vim (after-plugins)
" - ~/.vim/ftplugin/*.vim (filetype plugins)
" - ~/.vim/after/ftplugin/*.vim (after-filetype plugins)
" - And other standard Vim runtime directories
