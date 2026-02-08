@echo off
setlocal enabledelayedexpansion

REM call hooks
call "%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun

REM set %VISUAL% for chezmoi & others
for %%i in (nvim.exe vim.exe) do @if exist "%%~$PATH:i" (set VISUAL=%%~$PATH:i & goto :break)
:break

REM Check if the clink alias exists (which means Clink is injected)
where clink >nul 2>&1
doskey /macros | find /i "clink=" >nul 2>&1
if not errorlevel 1 (
  REM Clink is injected, so this is an interactive session
	call doskey /macrofile="%USERPROFILE%\.doskey.mac"

	REM unix-style prompt while still windows-y
	PROMPT %USERNAME%@%COMPUTERNAME% $P$G

	REM final fastfetch for both terminal-porn and usefulness since i switch between machines
	echo(
	call fastfetch

	REM just a clean line after clink injects
	REM need to do echo( to not just echo "" or ECHO is off.. boy, I love windows!
	echo(
)

