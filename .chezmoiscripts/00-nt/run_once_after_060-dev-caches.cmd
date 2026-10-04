@echo off

REM Package caches on the D: Dev Drive that 050-dev-drive creates. The
REM variables pointing each tool there are machine environment values in
REM .chezmoitemplates/registry-system.reg, imported by 000-registry; this
REM script makes the directories and moves any cache still sitting in a tool's
REM default location across.
REM
REM Each move happens only into an empty destination, i.e. once: on a
REM machine's first apply the mkdirs below have just created it, and on any
REM later run it already holds what was moved, so nothing moves again. Later
REM runs are not hypothetical -- chezmoi re-runs a run_once_ script whenever
REM its contents change -- and a second robocopy /MOVE would merge whatever had
REM since appeared in the old locations over the live caches on D:. Guarding
REM on the variables instead does not work: scoop's gradle sets a per-user
REM GRADLE_USER_HOME, which shadowed the machine one before registry-user.reg.
REM
REM `dir /b /a ... | findstr "^"` succeeds when the directory has any entry at
REM all, hidden ones included; `||` runs the move only when it does not.

if not exist D:\packages        mkdir D:\packages
if not exist D:\packages\npm    mkdir D:\packages\npm
if not exist D:\packages\nuget  mkdir D:\packages\nuget
if not exist D:\packages\vcpkg  mkdir D:\packages\vcpkg
if not exist D:\packages\pip    mkdir D:\packages\pip
if not exist D:\packages\cargo  mkdir D:\packages\cargo
if not exist D:\packages\maven  mkdir D:\packages\maven
if not exist D:\packages\gradle mkdir D:\packages\gradle

dir /b /a D:\packages\npm    2>nul | findstr "^" >nul || if exist "%AppData%\npm-cache"           robocopy "%AppData%\npm-cache"           D:\packages\npm    /E /MOVE
dir /b /a D:\packages\nuget  2>nul | findstr "^" >nul || if exist "%USERPROFILE%\.nuget\packages" robocopy "%USERPROFILE%\.nuget\packages" D:\packages\nuget  /E /MOVE
dir /b /a D:\packages\vcpkg  2>nul | findstr "^" >nul || if exist "%LOCALAPPDATA%\vcpkg\archives" robocopy "%LOCALAPPDATA%\vcpkg\archives" D:\packages\vcpkg  /E /MOVE
dir /b /a D:\packages\pip    2>nul | findstr "^" >nul || if exist "%LocalAppData%\pip\Cache"      robocopy "%LocalAppData%\pip\Cache"      D:\packages\pip    /E /MOVE
dir /b /a D:\packages\cargo  2>nul | findstr "^" >nul || if exist "%USERPROFILE%\.cargo"          robocopy "%USERPROFILE%\.cargo"          D:\packages\cargo  /E /MOVE
dir /b /a D:\packages\maven  2>nul | findstr "^" >nul || if exist "%USERPROFILE%\.m2\repository"  robocopy "%USERPROFILE%\.m2\repository"  D:\packages\maven  /E /MOVE
dir /b /a D:\packages\gradle 2>nul | findstr "^" >nul || if exist "%USERPROFILE%\.gradle"         robocopy "%USERPROFILE%\.gradle"         D:\packages\gradle /E /MOVE

REM ~/.cargo and ~/.gradle are not used at all on Windows (.chezmoiignore,
REM 065-tool-homes), so the folders a move just emptied go too. rmdir without
REM /s only ever removes an empty directory, so one that still holds anything
REM is left for 065-tool-homes to judge.
rmdir "%USERPROFILE%\.cargo"  2>nul
rmdir "%USERPROFILE%\.gradle" 2>nul

REM robocopy exits 1 when it copied files successfully (anything below 8 is
REM success), and the setx calls that used to end this script no longer do,
REM so leaving the last robocopy's code as the script's would fail the apply.
exit /b 0
