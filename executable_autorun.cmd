@echo off
setlocal enabledelayedexpansion

REM call hooks
call "%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun
call doskey /macrofile="%USERPROFILE%\.doskey.mac"

REM set VISUAL for chezmoi
where nvim.exe >nul 2>&1 && for /f "delims=" %i in ('where nvim.exe') do set "VISUAL=%i" && goto :break
where vim.exe >nul 2>&1 && for /f "delims=" %i in ('where vim.exe') do set "VISUAL=%i" && goto :break
:break

REM Check if the clink alias exists (which means Clink is injected)
where clink >nul 2>&1
clink info 2>nul | find /i "injected" >nul 2>&1
if %errorlevel%==0 (
	REM unix-style prompt while still windows-y
	PROMPT %USERNAME%@%COMPUTERNAME% $P$G

	REM final fastfetch for both terminal-porn and usefulness since i switch between machines
	echo(
	call fastfetch

	REM just a clean line after clink injects
	REM need to do echo( to not just echo "" or ECHO is off.. boy, I love windows!
	echo(
)

