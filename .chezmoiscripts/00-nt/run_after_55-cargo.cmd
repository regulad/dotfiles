@echo off
setlocal enabledelayedexpansion

if defined CARGO_HOME (
    set "CARGO_BIN=%CARGO_HOME%\bin"
) else (
    set "CARGO_BIN=%USERPROFILE%\.cargo\bin"
)

echo ;%PATH%; | find /I ";%CARGO_BIN%;" >nul
if errorlevel 1 (
    setx PATH "%PATH%;%CARGO_BIN%"
    echo Added %CARGO_BIN% to PATH.
) else (
    echo %CARGO_BIN% is already in PATH.
)

call refreshenv >nul 2>&1

where cargo >nul 2>&1
if not errorlevel 1 (
    echo cargo is already resolvable on PATH.
    goto :eof
)

call cargo install cargo-disasm
call cargo install vtracer 
call cargo install binwalk
