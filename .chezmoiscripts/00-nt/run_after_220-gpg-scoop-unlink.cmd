@echo off
setlocal enabledelayedexpansion

REM Git for Windows bundles its own MSYS2 gpg/gpg-agent/gpgconf/gpg-connect-agent,
REM and scoop's git manifest shims all four onto PATH. Gpg4win (installed via
REM winget in run_after_100-winget.cmd.tmpl) is the intended provider here: it is
REM the newer GnuPG core, and it is the one the HKLM\SOFTWARE\GnuPG registry key
REM and gpgme/Kleopatra actually agree on. Two GnuPG builds racing to answer for
REM the same agent socket is the same shape of collision as the Homebrew `gnupg`
REM unlink on Linux (00-linux/run_after_030-brew-extras.sh.tmpl) -- there it was
REM podman/gpgme pulling in a mismatched brew gnupg; here it is Git pulling in a
REM mismatched MSYS2 one.
REM
REM Placed after scoop's own install/update scripts (200/210) since it is
REM cleaning up shims those produce, not something git needs to exist yet.
REM
REM Runs every apply, not run_once: reinstalling or updating the git scoop
REM package regenerates its shims, so this has to keep re-removing them rather
REM than doing it once and drifting.
call where scoop >nul 2>&1
if %errorLevel% neq 0 (
    echo debug: scoop not on PATH, nothing to unlink yet
    goto :eof
)

for %%s in (gpg gpg-agent gpgconf gpg-connect-agent) do call :remove_if_git_shim %%s || goto :shim_rm_failed
goto :eof

REM `scoop shim list <name>` does a substring match on the name (so `scoop shim
REM list gpg` also returns gpg-agent/gpgconf/gpg-connect-agent), which is why the
REM findstr pattern below anchors on the line start and requires the name to be
REM followed immediately (mod whitespace) by "git" in the Source column, rather
REM than trusting the query to have already narrowed to one row.
REM
REM `scoop shim rm` exits nonzero when a shim doesn't exist, so removal is
REM guarded by that same check instead of trusted to no-op on repeated applies.
:remove_if_git_shim
call scoop shim list %1 2>nul | findstr /R /C:"^%1 *git" >nul 2>&1
if errorlevel 1 (
    echo debug: no git-sourced scoop shim for %1, skipping
    exit /b 0
)
echo debug: removing scoop shim %1 ^(sourced from git^)
call scoop shim rm %1
if errorlevel 1 (
    echo error: failed to remove scoop shim %1 1>&2
    exit /b 1
)
exit /b 0

:shim_rm_failed
echo error: scoop shim cleanup failed, aborting 1>&2
exit /b 1
