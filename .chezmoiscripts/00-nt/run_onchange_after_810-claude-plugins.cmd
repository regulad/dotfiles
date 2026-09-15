@echo off
REM Windows half of the Claude Code plugin bootstrap. The reasoning -- why this
REM is a script rather than part of the ~/.claude.json / settings.json merge,
REM and why it is append-only -- is written out once in
REM .chezmoitemplates/claude-plugins.sh; this is the same steps against the same
REM list. Ongoing updates are a separate every-apply pass,
REM 811-claude-plugin-update.cmd.
REM
REM The declared list is inlined below, so editing it retriggers this
REM run_onchange script on its own (no .tmpl / sha256sum trigger needed).
REM
REM claude is an npm .cmd shim on Windows, so every invocation is prefixed with
REM `call` -- without it, control transfers to the shim and never returns here.

setlocal

where claude >nul 2>nul
if errorlevel 1 (
    echo note: claude is not installed, skipping Claude Code plugin bootstrap 1>&2
    exit /b 0
)

call :add_marketplace wakatime wakatime/claude-code-wakatime
call :add_marketplace claude-plugins-official anthropics/claude-plugins-official

call :install_plugin claude-code-wakatime wakatime
call :install_plugin ralph-loop claude-plugins-official

endlocal
exit /b 0

REM Add marketplace %~1 from source %~2 if it is not already configured. The
REM presence check is a pipe, which cmd runs in a child process, so the shim
REM returns there without needing `call`.
:add_marketplace
claude plugin marketplace list 2>nul | findstr /I /C:"%~1" >nul 2>nul
if not errorlevel 1 (
    echo note: marketplace %~1 already configured 1>&2
    goto :eof
)
echo note: adding marketplace %~1 from %~2 1>&2
call claude plugin marketplace add %~2 || echo warning: failed to add marketplace %~1 1>&2
goto :eof

REM Install plugin %~1 from marketplace %~2 if it is not already installed.
:install_plugin
claude plugin list 2>nul | findstr /I /C:"%~1" >nul 2>nul
if not errorlevel 1 (
    echo note: plugin %~1 already installed 1>&2
    goto :eof
)
echo note: installing plugin %~1@%~2 1>&2
REM -y is required off-TTY and auto-accepts any marketplace-declared install
REM command; both sources here are plain git repos.
call claude plugin install %~1@%~2 -y || echo warning: failed to install %~1@%~2 1>&2
goto :eof
