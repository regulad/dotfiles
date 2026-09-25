@echo off
REM Windows counterpart of .chezmoitemplates/codex-plugins.sh.
REM Official plugin: https://wakatime.com/codex-cli-plugin
REM Retry each apply; do not remove other plugins or overwrite Codex config.
setlocal
where codex >nul 2>nul
if errorlevel 1 (
    echo note: codex is not installed, skipping Codex plugin bootstrap 1>&2
    exit /b 0
)
call codex plugin add --help >nul 2>nul
if errorlevel 1 (
    echo warning: update Codex to a version supporting 'plugin add' to install WakaTime 1>&2
    exit /b 0
)

REM Capture output first so a failed list cannot be mistaken for an empty list.
set "CODEX_PLUGIN_LIST=%TEMP%\chezmoi-codex-plugins-%RANDOM%-%RANDOM%.txt"
call codex plugin marketplace list >"%CODEX_PLUGIN_LIST%"
if errorlevel 1 goto :failed
findstr /R /C:"\<wakatime\>" "%CODEX_PLUGIN_LIST%" >nul
if errorlevel 1 (
    call codex plugin marketplace add wakatime/codex-cli-wakatime
    if errorlevel 1 goto :failed
)
REM --json lists installed plugins only, without --available.
call codex plugin list --marketplace wakatime --json >"%CODEX_PLUGIN_LIST%"
if errorlevel 1 goto :failed
findstr /L /C:"\"codex-cli-wakatime\"" "%CODEX_PLUGIN_LIST%" >nul
if errorlevel 1 (
    call codex plugin add codex-cli-wakatime@wakatime
    if errorlevel 1 goto :failed
)
del "%CODEX_PLUGIN_LIST%"
REM Uses the existing .wakatime.cfg; review/trust hooks in Codex if prompted.
exit /b 0

:failed
del "%CODEX_PLUGIN_LIST%"
echo error: Codex WakaTime plugin bootstrap failed; next apply will retry 1>&2
exit /b 1
