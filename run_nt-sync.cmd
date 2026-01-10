@echo off
setlocal enabledelayedexpansion

echo note: entering hookscript

REM Check Windows version
for /f "tokens=3" %%v in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul') do set BUILD=%%v
for /f "tokens=3" %%v in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v UBR 2^>nul') do set UBR=%%v

set VERSION=%BUILD%.%UBR%

REM Check if Windows 11 (build 22000+) with version >= 10.0.26200.7462
REM 2026-01-10: Current Windows 10 22H2 ESU patch is build 19045.6691 (KB5071546, December 2025)
if %BUILD% GEQ 22000 (
    if %BUILD% LSS 26200 (
        echo ERROR: Windows 11 version must be >= 10.0.26200.7462
        exit /b 1
    )
    if %BUILD% EQU 26200 (
        if %UBR% LSS 7462 (
            echo ERROR: Windows 11 version must be >= 10.0.26200.7462
            exit /b 1
        )
    )
) else if %BUILD% EQU 19045 (
    if %UBR% LSS 6691 (
        echo ERROR: Windows 10 22H2 must be at least build 19045.6691
        exit /b 1
    )
) else (
    echo ERROR: Windows version must be Windows 11 ^>= 10.0.26200.7462 or Windows 10 22H2 build 19045.6691+
    exit /b 1
)

REM Check for winget
where winget >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: winget is not available
    exit /b 1
)

where scoop >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command', 'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm get.scoop.sh | iex' -Wait"
)

call refreshenv >nul 2>&1

scoop update

set packages=bitwarden-cli chezmoi clink gh git nodejs nmap rust telnet unzip vim neovim uv

for %%p in (%packages%) do (
    scoop list %%p >nul 2>&1
    if !errorLevel! == 0 (
        scoop update %%p --quiet
    ) else (
        scoop install %%p
    )
)

clink autorun set %USERPROFILE%\autorun.cmd

call refreshenv >nul 2>&1

echo note: leaving hookscript