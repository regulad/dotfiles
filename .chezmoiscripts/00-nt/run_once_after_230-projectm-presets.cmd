@echo off
setlocal

REM Clones the projectM "Cream of the Crop" preset pack (~9,800 curated
REM Milkdrop presets), then flattens it: VLC bundles libprojectM 2.0.1
REM (contrib/src/projectM/rules.mak in vlc-3.0), whose preset loader is a
REM single non-recursive readdir() pass -- recursive scanning only landed
REM upstream in projectM-visualizer/projectm#385, in a major VLC never
REM adopted -- and the pack nests every preset in category subdirectories.
REM presets-flat is what dot_config/vlc/vlcrc points projectm-preset-path at:
REM hardlinks, so it costs no space, and the pack has no name collisions or
REM texture files to worry about. run_once + the exists guards: static
REM content, nothing to refresh on every apply.
REM
REM Plain setlocal, NO enabledelayedexpansion: preset names contain `!`,
REM which delayed expansion would mangle inside the for body. mklink /h
REM rather than PowerShell New-Item: New-Item's -Path/-Target glob wildcard
REM characters and choke on the `[bracketed]` preset names; the cmd builtin
REM takes paths literally (and hardlinks need no admin).

call where git >nul 2>&1
if %errorLevel% neq 0 (
    echo error: git not on PATH; 200-scoop-install.cmd should have installed it 1>&2
    exit /b 1
)

set preset_dir=%USERPROFILE%\.local\share\projectM\presets
set flat_dir=%USERPROFILE%\.local\share\projectM\presets-flat

if exist "%preset_dir%\.git" (
    echo note: projectM presets already present, skipping clone
) else (
    echo debug: cloning projectM presets
    git clone --depth 1 https://github.com/projectM-visualizer/presets-cream-of-the-crop "%preset_dir%"
    if errorlevel 1 (
        echo error: projectM preset clone failed 1>&2
        exit /b 1
    )
)

if exist "%flat_dir%" (
    echo note: flattened presets already present, skipping
    exit /b 0
)

REM Build in a temp dir and rename into place, so a half-built flat dir from
REM an interrupted run can never satisfy the exists-guard above.
echo debug: flattening presets into %flat_dir%
if exist "%flat_dir%.tmp" rd /s /q "%flat_dir%.tmp"
md "%flat_dir%.tmp"
for /r "%preset_dir%" %%f in (*.milk) do (
    mklink /h "%flat_dir%.tmp\%%~nxf" "%%f" >nul || (
        echo error: hardlink failed for %%f 1>&2
        exit /b 1
    )
)
move "%flat_dir%.tmp" "%flat_dir%" >nul
