@echo off
REM Update pass for both editors' plugin managers; runs on every apply. The
REM POSIX half is .chezmoitemplates/vim-plugin-update.sh (166 on linux/macos).
REM Installation and pinning live in 805-vim-plugins.cmd; this pass only moves
REM what is already declared forward.

setlocal

where vim >nul 2>nul
if errorlevel 1 (
    echo note: vim is not installed, skipping Vundle update 1>&2
    goto :nvim
)
if not exist "%USERPROFILE%\.vim\bundle\Vundle.vim" (
    echo note: Vundle not bootstrapped yet, skipping Vundle update 1>&2
    goto :nvim
)
REM :PluginUpdate is a `git pull` of each checkout's own tracking branch, so
REM the coc.nvim release pin set by 805 moves along origin/release rather than
REM being dragged back to the default branch. Same headless caveats as 805:
REM -E -s past the startup "Press ENTER" prompt, and Vundle exits non-zero
REM from ex mode even on success, so the exit code means nothing here.
echo note: updating vim plugins with Vundle 1>&2
vim -E -s -N -u "%USERPROFILE%\.vimrc" -c "PluginUpdate" -c "qall!" <nul >nul 2>nul

:nvim
where nvim >nul 2>nul
if errorlevel 1 (
    echo note: nvim is not installed, skipping lazy.nvim sync 1>&2
    exit /b 0
)
REM Lazy! sync rather than Lazy! update: install what is missing, update the
REM rest, and delete anything no longer declared in lua/plugins.lua -- the
REM plugin list is the whole truth on every apply, the same contract as
REM dot_vscode-extensions.txt. The bang makes headless nvim block until the
REM tasks finish instead of quitting mid-flight.
echo note: syncing nvim plugins with lazy.nvim 1>&2
nvim --headless "+Lazy! sync" +qa <nul
if errorlevel 1 (
    echo error: lazy.nvim sync failed 1>&2
    exit /b 1
)
exit /b 0
