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
    echo notice: claude is not installed, skipping Claude Code plugin bootstrap 1>&2
    exit /b 0
)

call :add_marketplace regulad regulad/skills
call :add_marketplace wakatime wakatime/claude-code-wakatime
call :add_marketplace claude-plugins-official anthropics/claude-plugins-official
call :add_marketplace openai-codex openai/codex-plugin-cc
call :add_marketplace cloudflare cloudflare/skills
call :add_marketplace onesignal OneSignal/onesignal-agent-plugin
call :add_marketplace googlechrome GoogleChrome/modern-web-guidance
call :add_marketplace microsoft-docs-marketplace MicrosoftDocs/mcp
call :add_marketplace chrome-devtools-plugins ChromeDevTools/chrome-devtools-mcp
call :add_marketplace trailofbits trailofbits/skills
call :add_marketplace astral-sh astral-sh/agent-plugins
call :add_marketplace docker docker/skills
call :add_marketplace typescript-skills microsoft/typescript-skills
call :add_marketplace android-skills android/skills
call :add_marketplace dotnet-agent-skills dotnet/skills

call :install_plugin regulad regulad
call :install_plugin claude-code-wakatime wakatime
call :install_plugin ralph-loop claude-plugins-official
call :install_plugin codex openai-codex
call :install_plugin vercel claude-plugins-official
call :install_plugin cloudflare cloudflare
call :install_plugin sentry claude-plugins-official
call :install_plugin sentry-cli claude-plugins-official
call :install_plugin supabase claude-plugins-official
call :install_plugin onesignal onesignal
call :install_plugin modern-web-guidance googlechrome
call :install_plugin microsoft-docs microsoft-docs-marketplace
call :install_plugin chrome-devtools-mcp chrome-devtools-plugins
call :install_plugin astral astral-sh
call :install_plugin docker-skills docker
call :install_plugin typescript typescript-skills
call :install_plugin android-skills android-skills
REM Windows only: the .NET SDK is installed only here (100-winget), and the
REM dotnet plugin's C# language server needs SDK 10's `dotnet dnx`.
call :install_plugin dotnet dotnet-agent-skills
call :install_plugin dotnet-upgrade dotnet-agent-skills

REM Trail of Bits' security plugins; which ones and why are in claude-plugins.sh.
for %%P in (c-review rust-review modern-cpp static-analysis sharp-edges insecure-defaults variant-analysis differential-review supply-chain-risk-auditor testing-handbook-skills property-based-testing dwarf-expert yara-authoring) do call :install_plugin %%P trailofbits

REM Language servers; which ones and why are in claude-plugins.sh. No
REM typescript-lsp or ruby-lsp here: Claude Code can't spawn their .cmd/.bat
REM wrappers (https://github.com/anthropics/claude-code/issues/51191).
call :install_plugin clangd-lsp claude-plugins-official
call :install_plugin gopls-lsp claude-plugins-official
call :install_plugin rust-analyzer-lsp claude-plugins-official
call :install_plugin jdtls-lsp claude-plugins-official

endlocal
exit /b 0

REM Add marketplace %~1 from source %~2 if it is not already configured. The
REM presence check is a pipe, which cmd runs in a child process, so the shim
REM returns there without needing `call`.
:add_marketplace
claude plugin marketplace list 2>nul | findstr /I /C:"%~1" >nul 2>nul
if not errorlevel 1 (
    echo debug: marketplace %~1 already configured 1>&2
    goto :eof
)
echo debug: adding marketplace %~1 from %~2 1>&2
call claude plugin marketplace add %~2 || echo warning: failed to add marketplace %~1 1>&2
goto :eof

REM Install plugin %~1 from marketplace %~2 if it is not already installed.
REM `plugin list` prints "plugin@marketplace"; matching the "@" too keeps
REM sentry from matching sentry-cli.
:install_plugin
claude plugin list 2>nul | findstr /I /C:"%~1@" >nul 2>nul
if not errorlevel 1 (
    echo debug: plugin %~1 already installed 1>&2
    goto :eof
)
echo debug: installing plugin %~1@%~2 1>&2
REM -y is required off-TTY and auto-accepts any marketplace-declared install
REM command; all sources here are plain git repos.
call claude plugin install %~1@%~2 -y || echo warning: failed to install %~1@%~2 1>&2
goto :eof
