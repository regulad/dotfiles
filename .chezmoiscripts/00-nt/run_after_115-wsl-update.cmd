@echo off
setlocal enabledelayedexpansion

REM Update half of the WSL setup; runs on every apply. Installing WSL and
REM enabling the optional Windows features lives in 110-wsl-install.cmd,
REM which is run_once.
REM
REM Worth keeping current rather than pinning: microsoft/WSL#40593 (systemd
REM user sessions failing across two distros that both have a uid-1000 user)
REM was fixed by microsoft/WSL#40519, and running an old WSL meant that bug
REM stayed live indefinitely.

call wsl.exe --version >nul 2>&1
if %errorLevel% neq 0 (
    echo error: WSL is not installed, or its optional Windows components need 1>&2
    echo error: a restart. 110-wsl-install.cmd should have handled the install. 1>&2
    exit /b 1
)

REM Exits 0 both when it updates and when it is already current -- verified
REM against 2.7.11, which prints "The most recent version ... is already
REM installed" and returns 0 -- so a non-zero here is a real failure.
REM
REM Note this restarts the WSL service when an update actually lands, which
REM terminates every running distro, Docker Desktop's included. That only
REM happens on a real update, not on the no-op path, so an apply against an
REM already-current WSL disturbs nothing.
echo debug: updating WSL
call wsl.exe --update
if errorlevel 1 (
    echo error: wsl --update failed 1>&2
    exit /b 1
)
