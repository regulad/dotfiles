@echo off
setlocal enabledelayedexpansion

echo note: installing python tooling
REM matches unix script. run_once keys on the script contents, so adding a tool
REM below changes the hash and this re-runs -- the list stays self-healing
REM without reinstalling everything on every apply. Upgrading what is already
REM installed lives in 501-python.cmd, which runs on every apply.
REM
REM The interpreter pins mirror the unix scripts; see the long NOTE in
REM 00-linux/100-python-tooling.sh for why each tool is pinned to a specific
REM CPython (or PyPy) rather than whatever uv would pick on its own.
REM
REM Differences from unix, both because the unix side gets these elsewhere:
REM   poetry - apt's python3-poetry / brew there, no NT package, so uv here
REM   hf     - brew (030-brew-extras) there, so uv here

REM the unix scripts run under `bash -e`, so a failing `uv tool install` aborts
REM the apply there. cmd carries on regardless, so check each one explicitly.
call :uvinstall -q "poetry" || goto :uv_install_failed
call :uvinstall -q "hf" || goto :uv_install_failed

call :uvinstall -q "ruff" || goto :uv_install_failed
call :uvinstall -q "ty" || goto :uv_install_failed

call :uvinstall --python "pypy@3.11" -q --with "bgutil-ytdlp-pot-provider" "yt-dlp[pin,pin-curl-cffi,pin-secretstorage,pin-deno]" || goto :uv_install_failed
call :uvinstall --python cp310 -q "frida-tools" || goto :uv_install_failed
call :uvinstall --python cp314 -q "keydive" || goto :uv_install_failed
call :uvinstall --python cp313 -q "pre-commit" || goto :uv_install_failed
call :uvinstall --python cp313 -q "mangadex-downloader[optional]" || goto :uv_install_failed
call :uvinstall --python cp310 -q "git+https://github.com/regulad/keymap-renderer.git@master" || goto :uv_install_failed
call :uvinstall --python cp314 -q "rendercv[full]@2.3" || goto :uv_install_failed
call :uvinstall --python cp314 -q "pymobiledevice3" || goto :uv_install_failed
call :uvinstall --python cp314 -q "claude-swap" || goto :uv_install_failed

call :uvinstall -q "hatch" || goto :uv_install_failed
call :uvinstall -q "autopep8" || goto :uv_install_failed

goto :eof

:uvinstall
uv tool install %*
if errorlevel 1 (
    echo error: uv tool install %* failed 1>&2
    exit /b 1
)
exit /b 0

:uv_install_failed
echo error: python tooling install failed, aborting 1>&2
exit /b 1
