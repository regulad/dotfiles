@echo off

REM Get current process ID
for /f "tokens=2 delims==" %%i in ('wmic process where "ProcessId=%PID%" get ParentProcessId /value 2^>nul') do set PARENT_PID=%%i
REM get DLLs loaded by process
tasklist /m /fi "PID eq %PID%" 2>nul | find /i "clink" >nul 2>&1
if %errorlevel% equ 0 (
    set CLINK_LOADED=1
) else (
    set CLINK_LOADED=
)


REM call hooks
call "%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun
call doskey /macrofile="%USERPROFILE%\.doskey.mac" 

REM set %VISUAL% for chezmoi & others
for %%i in (nvim.exe vim.exe) do @if exist "%%~$PATH:i" (set VISUAL=%%~$PATH:i & goto :break)
:break

REM Check if the clink alias exists (which means Clink is injected)
if defined CLINK_LOADED (
	REM clink injected, session is interactive.
	REM unix-style prompt while still windows-y
	PROMPT %USERNAME%@%COMPUTERNAME% $P$G

	REM final fastfetch for both terminal-porn and usefulness since i switch between machines
	echo(
	call fastfetch

	REM just a clean line after clink injects
	REM need to do echo( to not just echo "" or ECHO is off.. boy, I love windows!
	echo(
)
