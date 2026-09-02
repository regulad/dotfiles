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
call :uvinstall --python cp314 -q "keydive" || goto :uv_install_failed
call :uvinstall --python cp313 -q "pre-commit" || goto :uv_install_failed
call :uvinstall --python cp313 -q "mangadex-downloader[optional]" || goto :uv_install_failed
call :uvinstall --python cp310 -q "git+https://github.com/regulad/keymap-renderer.git@master" || goto :uv_install_failed

REM pinned to the frida-server version the device actually runs -- the binding
REM and the server only speak to each other at the same version, and 16.7.0 is
REM the newest re.frida.server hosted for roothide devices at
REM https://miticollo.github.io/repos/roothide/Packages, since the 17.x major
REM family has yet to be ported there. frida-tools' own frida>=16.2.2,<17.0.0 is
REM loose enough to drift to 16.7.19, so the --with is what holds it. See the
REM long NOTE in 00-linux/run_after_100-python-tooling.sh.tmpl.
call :uvinstall --python cp312 -q --with "frida==16.7.0" "frida-tools==13.7.1" || goto :uv_install_failed

REM 2.3 onward are LLM slop, and 2.2 is the last version that didn't change the
REM schema. cp313 because 2.2 wants pydantic-core 2.27.2, which has no cp314
REM wheel. The --with pins cap rendercv 2.2's transitive deps that it left loose
REM -- rendercv-fonts, click, rich and jinja2 -- because 2.2 is frozen while the
REM `uv tool upgrade --all` in 501-python.cmd re-resolves anything unpinned. See
REM the long NOTE in 00-linux/run_after_100-python-tooling.sh.tmpl for what each
REM cap prevents.
call :uvinstall --python cp313 -q --with "rendercv-fonts<0.5" --with "click<8.2" --with "rich<11" --with "jinja2<4" "rendercv[full]@2.2" || goto :uv_install_failed

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
