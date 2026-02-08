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

echo debug: installing scoop
where scoop >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command', 'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm get.scoop.sh | iex' -Wait"
)
call refreshenv >nul 2>&1

echo debug: installing scoop packages
call scoop update
call scoop bucket add extras >nul 2>&1
set packages=^
bitwarden-cli ^
chezmoi ^
clink ^
gh ^
git ^
nodejs ^
nmap ^
rust ^
telnet ^
unzip ^
vim ^
neovim ^
uv ^
file ^
dos2unix ^
grep ^
gradle ^
coreutils ^
openssl ^
wingetcreate ^
autohotkey

for %%p in (%packages%) do (
    call scoop list %%p >nul 2>&1
    if !errorLevel! neq 0 (
        call scoop install %%p
    )
)

echo debug: updating existing scoop packages
call scoop update --all >nul

echo debug: setting autorun
call clink autorun set %USERPROFILE%\autorun.cmd >nul 2>&1

echo debug: installing winget packages
REM Install/update winget packages
set winget_packages=^
Microsoft.WindowsTerminal ^
Element.Element ^
JetBrains.Toolbox ^
Zoom.Zoom.EXE ^
PrismLauncher.PrismLauncher ^
OpenWhisperSystems.Signal ^
Bitwarden.Bitwarden ^
Jellyfin.JellyfinMediaPlayer ^
Anthropic.Claude ^
WinSCP.WinSCP ^
GnuPG.GnuPG ^
MHNexus.HxD ^
VideoLAN.VLC ^
PuTTY.PuTTY ^
EclipseAdoptium.Temurin.25.JDK ^
EclipseAdoptium.Temurin.21.JDK ^
OpenJS.NodeJS.LTS ^
DenoLand.Deno ^
Microsoft.VisualStudioCode ^
Autodesk.DesktopApp ^
TeamViewer.TeamViewer ^
Syncthing.Syncthing

for %%p in (%winget_packages%) do (
    echo Checking %%p...
    call winget list --id %%p --exact >nul 2>&1
    if !errorLevel! == 0 (
        echo Updating %%p...
        call winget upgrade --id %%p --silent --accept-source-agreements --accept-package-agreements
    ) else (
        echo Installing %%p...
        call winget install --id %%p --silent --accept-source-agreements --accept-package-agreements
    )
)

REM Setup symlinks from windows-specific AppData into the XDG .config directory
set local_links=^
nvim

for %%L in (%local_links%) do (
    if exist "%USERPROFILE%\AppData\Local\%%L" (
        for %%i in ("%USERPROFILE%\AppData\Local\%%L") do set "attribs=%%~ai"
        setlocal enabledelayedexpansion
        if not "!attribs:~8,1!"=="l" (
            echo warning: existing %%L directory exists
        )
        endlocal
    ) else (
        mklink /J "%USERPROFILE%\AppData\Local\%%L" "%USERPROFILE%\.config\%%L"
    )
)

set roaming_links=^
Code

for %%L in (%roaming_links%) do (
    if exist "%USERPROFILE%\AppData\Roaming\%%L" (
        for %%i in ("%USERPROFILE%\AppData\Roaming\%%L") do set "attribs=%%~ai"
        setlocal enabledelayedexpansion
        if not "!attribs:~8,1!"=="l" (
            echo warning: existing %%L directory exists
        )
        endlocal
    ) else (
        mklink /J "%USERPROFILE%\AppData\Roaming\%%L" "%USERPROFILE%\.config\%%L"
    )
)

call refreshenv >nul 2>&1

echo note: leaving hookscript
