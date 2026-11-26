:neosetx
REM drop-in setx replacement that isn't limited to 1024 characters (setx silently
REM truncates anything longer, which corrupts PATH once it grows past that length).
REM usage: call :neosetx <VARNAME> <VALUE> [/M]
setlocal
set "_NEOSETX_VAR=%~1"
set "_NEOSETX_VAL=%~2"
set "_NEOSETX_SCOPE=User"
if /I "%~3"=="/M" set "_NEOSETX_SCOPE=Machine"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "[Environment]::SetEnvironmentVariable($env:_NEOSETX_VAR, $env:_NEOSETX_VAL, $env:_NEOSETX_SCOPE)"
echo debug: neosetx set %_NEOSETX_SCOPE%-scope %_NEOSETX_VAR% via PowerShell >&2
endlocal
exit /b
