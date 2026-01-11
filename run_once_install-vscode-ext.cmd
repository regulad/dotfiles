@echo off
where code >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    for /F "tokens=*" %%A in (%USERPROFILE%\vscode-extensions.txt) do (
        call code --install-extension %%A --force
    )
) else (
    echo VSCode 'code' command not found in PATH, skipping extension installation
)

