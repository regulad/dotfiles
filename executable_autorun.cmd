@echo off
REM enabling delayed expansion breaks everything. i hate windows scripts so much
REM per claude sonnet 4.5, this should work
setlocal EnableDelayedExpansion
set "_ccl_=!cmdcmdline!"
if "!_ccl_:~1,-2!" == "!comspec!" (
    endlocal & set "INTERACTIVE=1"
) else (
    endlocal & set "INTERACTIVE="
)

REM call hooks
call "%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun
call doskey /macrofile="%USERPROFILE%\.doskey.mac" 

REM set %VISUAL% for chezmoi & others
for %%i in (nvim.exe vim.exe) do @if exist "%%~$PATH:i" (set VISUAL=%%~$PATH:i & goto :break)
:break

REM Check if the clink alias exists (which means Clink is injected)
if defined INTERACTIVE (
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
