:goinstall
REM usage: call :goinstall <module>@<version>
REM go install with three tries, 10 and 30 seconds apart, as the unix scripts'
REM `retry -t 3 -d 10,30` (.chezmoitemplates/go-tooling.sh): the module proxy
REM and the checksum database each have the occasional bad minute. Exits 1
REM once the last try has failed too.
setlocal
set /a _GOINSTALL_TRY=0
:goinstall_try
set /a _GOINSTALL_TRY+=1
go install %1
if not errorlevel 1 (
    endlocal
    exit /b 0
)
if %_GOINSTALL_TRY% geq 3 (
    echo error: go install %1 failed after %_GOINSTALL_TRY% tries 1>&2
    endlocal
    exit /b 1
)
set "_GOINSTALL_WAIT=30"
if %_GOINSTALL_TRY% equ 1 set "_GOINSTALL_WAIT=10"
echo warning: go install %1 failed ^(try %_GOINSTALL_TRY% of 3^), retrying in %_GOINSTALL_WAIT% seconds 1>&2
powershell -NoProfile -NonInteractive -Command "Start-Sleep -Seconds %_GOINSTALL_WAIT%"
goto :goinstall_try
