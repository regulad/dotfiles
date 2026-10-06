@echo off
REM Windows counterpart of .chezmoitemplates/codex-plugins.sh, which says where
REM each plugin comes from; this is the same steps against the same lists.
REM Retry each apply; do not remove other plugins or overwrite Codex config.
setlocal
where codex >nul 2>nul
if errorlevel 1 (
    echo notice: codex is not installed, skipping Codex plugin bootstrap 1>&2
    exit /b 0
)
call codex plugin add --help >nul 2>nul
if errorlevel 1 (
    echo warning: update Codex to a version supporting 'plugin add' to install plugins 1>&2
    exit /b 0
)

REM Capture output first so a failed list cannot be mistaken for an empty list.
set "CODEX_PLUGIN_LIST=%TEMP%\chezmoi-codex-plugins-%RANDOM%-%RANDOM%.txt"
set "FAILED="
set "CURATED="

call codex plugin marketplace list >"%CODEX_PLUGIN_LIST%"
if errorlevel 1 (
    set "FAILED=1"
    goto :plugins
)
call :add_marketplace wakatime wakatime/codex-cli-wakatime
call :add_marketplace cloudflare cloudflare/skills
REM OpenAI's curated marketplace is openai-curated under a ChatGPT login,
REM openai-api-curated otherwise, and absent until Codex's first interactive
REM start syncs it.
findstr /B /L /C:"openai-curated " "%CODEX_PLUGIN_LIST%" >nul && set "CURATED=openai-curated"
if not defined CURATED findstr /B /L /C:"openai-api-curated " "%CODEX_PLUGIN_LIST%" >nul && set "CURATED=openai-api-curated"

:plugins
call :add_plugin codex-cli-wakatime wakatime
call :add_plugin cloudflare cloudflare
if defined CURATED (
    call :add_plugin vercel %CURATED%
) else (
    echo notice: Codex has not synced its curated marketplace yet, skipping vercel; start codex once and re-apply 1>&2
)

del "%CODEX_PLUGIN_LIST%" 2>nul
REM Review/trust plugin hooks in Codex if prompted.
if defined FAILED (
    echo error: Codex plugin bootstrap failed; next apply will retry 1>&2
    exit /b 1
)
exit /b 0

REM Add marketplace %~1 from source %~2 unless the captured list has it.
:add_marketplace
findstr /B /L /C:"%~1 " "%CODEX_PLUGIN_LIST%" >nul
if not errorlevel 1 goto :eof
echo debug: adding Codex marketplace %~1 from %~2 1>&2
call codex plugin marketplace add %~2
if errorlevel 1 set "FAILED=1"
goto :eof

REM Install plugin %~1 from marketplace %~2 unless it is already installed.
REM This overwrites the captured list. --json lists installed plugins only,
REM without --available.
:add_plugin
call codex plugin list --marketplace %~2 --json >"%CODEX_PLUGIN_LIST%"
if errorlevel 1 (
    set "FAILED=1"
    goto :eof
)
findstr /L /C:"\"%~1@%~2\"" "%CODEX_PLUGIN_LIST%" >nul
if not errorlevel 1 goto :eof
echo debug: installing Codex plugin %~1@%~2 1>&2
call codex plugin add %~1@%~2
if errorlevel 1 set "FAILED=1"
goto :eof
