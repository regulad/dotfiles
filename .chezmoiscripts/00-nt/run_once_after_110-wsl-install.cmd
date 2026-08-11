@echo off
setlocal enabledelayedexpansion

REM Install half of the WSL setup. Keeping it current lives in
REM 115-wsl-update.cmd, which runs on every apply; this one is run_once.
REM
REM Ordered after 100-winget.cmd so winget is available, though this uses
REM wsl.exe's own installer rather than the Microsoft.WSL winget package:
REM `wsl --install` also enables the VirtualMachinePlatform and
REM Microsoft-Windows-Subsystem-Linux optional Windows features, which
REM installing the store package alone does not.

REM --version is the honest test. wsl.exe itself is a stub present on every
REM Windows 11 install whether or not WSL is actually there, so `where wsl`
REM would always succeed; --version only exits 0 once the real package is in.
call wsl.exe --version >nul 2>&1
if %errorLevel% equ 0 (
    echo debug: WSL already installed, skipping
    exit /b 0
)

REM --no-distribution: this repo ships its own images (see
REM .github/workflows/wsl-package.yml), so there is no reason to drag in the
REM default Ubuntu and then have to unregister it.
echo debug: installing WSL ^(optional components only, no distribution^)
call sudo wsl.exe --install --no-distribution
if errorlevel 1 (
    echo error: wsl --install --no-distribution failed 1>&2
    exit /b 1
)

REM Enabling the optional Windows features needs a restart before wsl can
REM actually run anything. There is no reliable way to detect from here
REM whether they were already on, so say so unconditionally rather than let a
REM later script fail confusingly.
echo note: if WSL's optional Windows components were just enabled, restart 1>&2
echo note: Windows before using wsl. 115-wsl-update.cmd will fail until then. 1>&2
