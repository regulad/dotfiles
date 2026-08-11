@echo off
setlocal enabledelayedexpansion

REM Update half of the scoop setup; runs on every apply. Bootstrapping scoop,
REM adding buckets, installing packages and registering services all live in
REM 200-scoop-install.cmd, which is run_once.

call where scoop >nul 2>&1
if %errorLevel% neq 0 (
    echo error: scoop not on PATH; 200-scoop-install.cmd should have installed it 1>&2
    exit /b 1
)

REM Refreshes scoop itself and the bucket manifests.
echo debug: updating scoop and bucket manifests
call scoop update
if errorlevel 1 (
    echo error: scoop update failed 1>&2
    exit /b 1
)

REM Upgrades every installed package to the manifest version fetched above.
echo debug: updating installed scoop packages
call scoop update --all
if errorlevel 1 (
    echo error: scoop update --all failed 1>&2
    exit /b 1
)

call refreshenv >nul 2>&1
