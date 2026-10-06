@echo off
REM Windows half of .chezmoitemplates/reminders.sh, which says what each check
REM is for: the per-machine sign-ins chezmoi cannot do itself, checked first and
REM only mentioned while still outstanding. Numbered last so they are the final
REM lines of an apply.
REM
REM Direct invocations are prefixed with `call`, which an npm .cmd shim needs to
REM return here; ones on the left of a pipe run in a child cmd and do not.

setlocal
call :check_claude
call :check_codex
call :check_cf
endlocal
exit /b 0

:check_claude
where claude >nul 2>nul
if errorlevel 1 (
    echo debug: claude is not installed, skipping its sign-in reminder 1>&2
    goto :eof
)
call claude auth status >nul 2>nul <nul
if errorlevel 1 (
    echo notice: Claude Code is not signed in; start claude and run /login 1>&2
) else (
    echo debug: Claude Code is signed in 1>&2
)
claude mcp get plugin:cloudflare:cloudflare 2>nul <nul | findstr /L /C:"Needs authentication" >nul
if not errorlevel 1 (
    echo notice: Claude Code is not signed in to Cloudflare's MCP server; run /mcp in claude and authenticate plugin:cloudflare:cloudflare 1>&2
)
goto :eof

:check_codex
where codex >nul 2>nul
if errorlevel 1 (
    echo debug: codex is not installed, skipping its reminder 1>&2
    goto :eof
)
call codex login status >nul 2>nul <nul
if errorlevel 1 (
    echo notice: Codex is not signed in; run codex once and sign in 1>&2
    goto :codex_mcp
)
codex plugin marketplace list 2>nul <nul | findstr /B /L /C:"openai-curated " /C:"openai-api-curated " >nul
if errorlevel 1 (
    echo notice: Codex has not synced its curated plugin marketplace; run codex once, then re-apply to install the vercel plugin 1>&2
) else (
    echo debug: Codex is signed in and has its curated plugin marketplace 1>&2
)
:codex_mcp
codex mcp list 2>nul <nul | findstr /R /C:"^cloudflare .*Not logged in" >nul
if not errorlevel 1 (
    echo notice: Codex is not signed in to Cloudflare's MCP server; run codex mcp login cloudflare 1>&2
)
goto :eof

:check_cf
where cf >nul 2>nul
if errorlevel 1 (
    echo debug: cf is not installed, skipping its sign-in reminder 1>&2
    goto :eof
)
cf auth whoami 2>nul <nul | findstr /L /C:"\"authenticated\": true" >nul
if errorlevel 1 (
    echo notice: cf is not signed in; run cf auth login 1>&2
) else (
    echo debug: cf is signed in 1>&2
)
goto :eof
