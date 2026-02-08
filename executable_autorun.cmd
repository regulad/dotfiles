@echo off
setlocal enabledelayedexpansion

REM call hooks
call "%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun
call doskey /macrofile="%USERPROFILE%\.doskey.mac" 


REM unix-style prompt while still windows-y
PROMPT %USERNAME%@%COMPUTERNAME% $P$G

REM putting the conditional breaks set??? idfk why
REM set %VISUAL% for chezmoi & others
for %%i in (nvim.exe vim.exe) do @if exist "%%~$PATH:i" (set VISUAL=%%~$PATH:i & goto :break)
:break
