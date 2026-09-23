@echo off
REM Update pass for Claude Code plugins; runs on every apply. Installation and
REM the declared list live in 810-claude-plugins.cmd; this pass only moves what
REM is already installed forward. `claude plugin update` reports "restart
REM required to apply", which is expected and applies on the next Claude Code
REM start. POSIX half: .chezmoitemplates/claude-plugin-update.sh.
REM
REM claude is an npm .cmd shim on Windows, so every direct invocation is
REM prefixed with `call` -- without it, control transfers to the shim and never
REM returns here. (Invocations on the left of a pipe are exempt: cmd runs the
REM pipe in a child process.)

setlocal

where claude >nul 2>nul
if errorlevel 1 (
    echo note: claude is not installed, skipping Claude Code plugin update 1>&2
    exit /b 0
)

echo note: updating Claude Code marketplaces 1>&2
call claude plugin marketplace update || echo warning: marketplace update failed 1>&2

REM Kept in step with the bootstrap's declared plugins. `claude plugin update`
REM needs an explicit name (there is no update-all), and the guard skips any a
REM given machine has not installed.
for %%P in (claude-code-wakatime ralph-loop codex) do call :update_plugin %%P

endlocal
exit /b 0

:update_plugin
claude plugin list 2>nul | findstr /I /C:"%~1" >nul 2>nul
if errorlevel 1 goto :eof
echo note: updating plugin %~1 1>&2
call claude plugin update %~1 || echo warning: failed to update %~1 1>&2
goto :eof
