@echo off
setlocal enabledelayedexpansion

call where scoop >nul 2>&1
if %errorLevel% neq 0 (
    echo debug: installing scoop
    call powershell -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command', 'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm get.scoop.sh | iex' -Wait"
)
call refreshenv >nul 2>&1

echo debug: updating scoop
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
deno ^
mongosh ^
mongodb-compass ^
mpv ^
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
rclone ^
less ^
imagemagick ^
autohotkey ^
languagetool-java ^
nssm

REM Complex command blocks inside for loops break cmd's parser even without pipes.
REM Subroutine call isolates each package check cleanly. Fix by Claude Sonnet 4.6 (Anthropic).
echo debug: installing new scoop user packages
for %%p in (%user_packages%) do call :check_install_user %%p
goto :after_check_install_user

:check_install_user
scoop list %1 2>nul | findstr /r /c:"%1  *[0-9]" >nul 2>&1
if errorlevel 1 (
    echo debug: %1 not installed, installing...
    scoop install %1
) else (
    echo debug: %1 already installed, skipping
)
exit /b

:after_check_install_user

REM prompts mpv to use the chezmoi provided config in .config
Remove-Item "$env:USERPROFILE\scoop\apps\mpv\current\portable_config" -Recurse -Force

set admin_packages=^
icaros-np

echo debug: installing new scoop admin packages
for %%p in (%admin_packages%) do call :check_install_admin %%p
goto :after_check_install_admin

:check_install_admin
scoop list %1 2>nul | findstr /r /c:"%1  *[0-9]" >nul 2>&1
if errorlevel 1 (
    echo debug: %1 not installed, installing...
    sudo scoop install %1
) else (
    echo debug: %1 already installed, skipping
)
exit /b

:after_check_install_admin

call refreshenv >nul 2>&1

echo debug: updating existing scoop packages
call scoop update --all
call refreshenv >nul 2>&1

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
