@echo off

REM call hooks
call "%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun
call doskey /macrofile="%USERPROFILE%\.doskey.mac" 

REM set %VISUAL% for chezmoi & others
for %%i in (nvim.exe vim.exe) do @if exist "%%~$PATH:i" (set VISUAL=%%~$PATH:i & goto :break)
:break

REM other environment variables
REM DO NOT INCLUDE QUOTES!
set RCLONE_CONFIG=%USERPROFILE%\.config\rclone\rclone.conf

REM display fancy stuff if this is an interactive session
echo %CMDCMDLINE% | findstr /I /C:"/C" >nul && goto :end || goto :interactive

:interactive
REM padding from clink
echo(

REM unix-style prompt while still windows-y
PROMPT %USERNAME%@%COMPUTERNAME% $P$G

REM final fastfetch for both terminal-porn and usefulness since i switch between machines
call fastfetch
REM can't do a padding after it because clink strips the last newline before the prompt
:end
