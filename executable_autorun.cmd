@echo off

REM call hooks
call "%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun
call doskey /macrofile="%USERPROFILE%\.doskey.mac" 

REM this is the only way to check to see if clink is injected into the process,
REM which is the only good tell if the process is interactive without native code
REM (clink uses native code to walk the "caller" tree)
REM problem is, it spawns a cmd subtask. that won't do because calling a CMD subtask
REM will also call autorun.cmd, causing recursion :)

REM REM Get current process ID
REM for /f "tokens=2 delims==" %%i in ('wmic process where "ProcessId=%PID%" get ParentProcessId /value 2^>nul') do set PARENT_PID=%%i
REM REM get DLLs loaded by process
REM tasklist /m /fi "PID eq %PID%" 2>nul | find /i "clink" >nul 2>&1
REM if %errorlevel% equ 0 (
REM     set CLINK_LOADED=1
REM ) else (
REM     set CLINK_LOADED=
REM )

REM set %VISUAL% for chezmoi & others
for %%i in (nvim.exe vim.exe) do @if exist "%%~$PATH:i" (set VISUAL=%%~$PATH:i & goto :break)
:break

REM other environment variables
set RCLONE_CONFIG="%USERPROFILE%\.config\rclone\rclone.conf"

REM unix-style prompt while still windows-y
PROMPT %USERNAME%@%COMPUTERNAME% $P$G

REM final fastfetch for both terminal-porn and usefulness since i switch between machines
echo(
call fastfetch

REM just a clean line after clink injects
REM need to do echo( to not just echo "" or ECHO is off.. boy, I love windows!
echo(
