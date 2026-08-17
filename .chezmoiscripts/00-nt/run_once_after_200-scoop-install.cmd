@echo off
setlocal enabledelayedexpansion

REM Install half of the scoop setup. Upgrading existing packages lives in
REM 210-scoop-update.cmd, which runs on every apply; this one is run_once.
REM
REM run_once keys on the script contents, so adding a package to either list
REM below changes the hash and this re-runs -- the lists stay self-healing
REM without needing to reinstall everything on every apply.

call where scoop >nul 2>&1
if %errorLevel% neq 0 (
    echo debug: installing scoop
    call powershell -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command', 'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm get.scoop.sh | iex' -Wait"
)
call refreshenv >nul 2>&1

REM Refresh bucket manifests before installing, or a stale checkout installs a
REM stale version. This is manifest refresh, not package upgrade -- the latter
REM is `scoop update --all` and belongs to 210-scoop-update.cmd.
echo debug: refreshing scoop manifests
call scoop update

call scoop bucket list | findstr /R /C:"^extras " >nul 2>&1
if errorlevel 1 (
    echo Adding extras bucket...
    call scoop bucket add extras
) else (
    echo extras bucket already present, skipping.
)
call scoop bucket list | findstr /R /C:"^versions " >nul 2>&1
if errorlevel 1 (
    echo Adding versions bucket...
    call scoop bucket add versions
) else (
    echo versions bucket already present, skipping.
)
call scoop bucket list | findstr /R /C:"^nonportable " >nul 2>&1
if errorlevel 1 (
    echo Adding nonportable bucket...
    call scoop bucket add nonportable
) else (
    echo nonportable already present, skipping.
)
call scoop bucket list | findstr /R /C:"^games " >nul 2>&1
if errorlevel 1 (
    echo Adding games bucket...
    call scoop bucket add games
) else (
    echo games already present, skipping.
)

call scoop bucket list | findstr /R /C:"^regulad " >nul 2>&1
if errorlevel 1 (
    echo Adding regulad bucket...
    call scoop bucket add regulad https://github.com/regulad/scoop-regulad.git
) else (
    echo regulad bucket already present, skipping.
)
call scoop bucket list | findstr /R /C:"^psmux " >nul 2>&1
if errorlevel 1 (
    echo Adding psmux bucket...
    call scoop bucket add psmux https://github.com/marlocarlo/scoop-psmux
) else (
    echo psmux bucket already present, skipping.
)

set user_packages=^
iperf3 ^
tinyxnb ^
shasum ^
deno ^
mongosh ^
mongodb-compass ^
mpv ^
act ^
git-filter-repo ^
python27 ^
dtk ^
ninja ^
bitwarden-cli ^
chezmoi ^
psmux ^
clink ^
gh ^
git ^
ffdec ^
nodejs ^
gow ^
bind ^
pnpm ^
nmap ^
npiperelay ^
rust ^
go ^
fastfetch ^
ripgrep ^
actionlint ^
hadolint ^
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
rclone ^
less ^
imagemagick ^
autohotkey ^
languagetool-java ^
nssm

REM Complex command blocks inside for loops break cmd's parser even without pipes.
REM Subroutine call isolates each package check cleanly. Fix by Claude Sonnet 4.6 (Anthropic).
echo debug: installing new scoop user packages
for %%p in (%user_packages%) do call :check_install_user %%p || goto :scoop_install_failed
goto :after_check_install_user

:check_install_user
scoop list %1 2>nul | findstr /r /c:"%1  *[0-9]" >nul 2>&1
if errorlevel 1 (
    echo debug: %1 not installed, installing...
    scoop install %1
    if errorlevel 1 (
        echo error: failed to install scoop package %1 1>&2
        exit /b 1
    )
) else (
    echo debug: %1 already installed, skipping
)
exit /b 0

:after_check_install_user

REM prompts mpv to use the chezmoi provided config in .config
REM NOTE: this was a PowerShell Remove-Item line sitting in a .cmd file, so cmd
REM reported "not recognized as an internal or external command" and carried on
REM -- the directory was never actually removed and mpv kept using its portable
REM config. Rewritten in cmd, and guarded so a missing directory is not an error.
if exist "%USERPROFILE%\scoop\apps\mpv\current\portable_config" (
    echo debug: removing mpv portable_config so the chezmoi config in .config wins
    rmdir /s /q "%USERPROFILE%\scoop\apps\mpv\current\portable_config"
    if errorlevel 1 (
        echo error: failed to remove mpv portable_config 1>&2
        exit /b 1
    )
)

set admin_packages=^
icaros-np

echo debug: installing new scoop admin packages
for %%p in (%admin_packages%) do call :check_install_admin %%p || goto :scoop_install_failed
goto :after_check_install_admin

:check_install_admin
scoop list %1 2>nul | findstr /r /c:"%1  *[0-9]" >nul 2>&1
if errorlevel 1 (
    echo debug: %1 not installed, installing...
    sudo scoop install %1
    if errorlevel 1 (
        echo error: failed to install scoop package %1 1>&2
        exit /b 1
    )
) else (
    echo debug: %1 already installed, skipping
)
exit /b 0

:after_check_install_admin

call refreshenv >nul 2>&1

REM `scoop update --all` used to be here; it upgrades already-installed
REM packages, which is an every-apply concern, so it moved to
REM 210-scoop-update.cmd.

echo debug: setting autorun
call clink autorun set %USERPROFILE%\autorun.cmd >nul 2>&1

REM service setup
call sc query LanguageTool >nul 2>&1
if !errorLevel! neq 0 (
    echo Registering LanguageTool service...
    set LT_PATH=%USERPROFILE%\scoop\apps\languagetool-java\current
    call sudo nssm install LanguageTool "%JAVA_HOME%bin\java.exe"
    call sudo nssm set LanguageTool AppParameters "-cp \"!LT_PATH!\languagetool-server.jar\" org.languagetool.server.HTTPServer --port 8081 --allow-origin \"*\""
    call sudo nssm set LanguageTool AppDirectory "!LT_PATH!"
    call sudo nssm set LanguageTool Start SERVICE_AUTO_START
    call sudo nssm start LanguageTool
    echo LanguageTool service registered and started.
) else (
    echo LanguageTool service already registered, skipping.
)

goto :eof

:scoop_install_failed
echo error: scoop package install failed, aborting 1>&2
exit /b 1
