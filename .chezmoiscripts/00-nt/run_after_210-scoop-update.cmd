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

REM Old versions. An update installs the new version beside the old one and
REM moves the `current` junction over, and never removes the old one: on
REM 2026-11-13 that was 340 old versions of 50 apps, 47 GiB, eleven Rust
REM toolchains of about 1.3 GiB each among them. `scoop cleanup --all` removes
REM every version but the current one; --cache drops the downloads of versions
REM no longer installed. Nothing points into a versioned directory: shims, the
REM nssm services and the environment all go through `current`, and persist\
REM is not touched. Every app is a per-user install, so no -g, which would
REM need elevation.
REM
REM Best-effort. A file still in use -- a program started before its update,
REM a shell extension Explorer has loaded -- keeps its old version on disk;
REM scoop says so and carries on, and the next apply tries again. Its exit
REM status says nothing either way (see :scoop_install in 200-scoop-install),
REM so what is left is counted afterwards.
echo debug: removing old versions of scoop packages and their downloads
call scoop cleanup --all --cache
powershell -NoProfile -NonInteractive -Command "$left = foreach ($d in Get-ChildItem (Join-Path $env:USERPROFILE 'scoop\apps') -Directory) { $c = Get-Item -LiteralPath (Join-Path $d.FullName 'current') -ErrorAction SilentlyContinue; if ($c -and $c.Target) { $t = Split-Path -Leaf @($c.Target)[0]; $old = @(Get-ChildItem -LiteralPath $d.FullName -Directory | Where-Object { $_.Name -ne 'current' -and $_.Name -ne $t }); if ($old.Count) { $d.Name + ' ' + ($old.Name -join ',') } } }; if ($left) { Write-Host ('warning: old scoop versions still on disk, probably in use; the next apply retries: ' + ($left -join '; ')) } else { Write-Host 'debug: no old scoop versions left' }"

call refreshenv >nul 2>&1
