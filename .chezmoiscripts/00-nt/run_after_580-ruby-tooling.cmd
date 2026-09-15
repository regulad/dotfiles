@echo off
REM Ruby gem tooling; runs on every apply. Mirrors the POSIX side, where
REM 030-brew-extras installs both through brew-gem: ruby-lsp is the ruby_lsp
REM language server enabled in nvim's init.lua, and neovim is the ruby
REM provider bridge gem (:checkhealth vim.provider). Ruby itself comes from
REM scoop (200-scoop-install.cmd).
REM
REM scoop persists the gems dir across ruby upgrades (persist: gems), so
REM installed gems normally survive updates; the per-gem presence check below
REM is what re-heals after the cases persist can't cover, like a major ruby
REM bump resetting the gem ABI.

setlocal

REM scoop's ruby package puts bin dirs on user PATH via env_add_path rather
REM than shims, and that hasn't propagated into this session on a first apply
REM -- same trap 570-pnpm-tooling.cmd documents for pnpm. Fall back to the
REM install location itself.
set "GEM=gem"
call where gem >nul 2>&1
if errorlevel 1 set "GEM=%USERPROFILE%\scoop\apps\ruby\current\bin\gem.cmd"
if not exist "%GEM%" (
    call where gem >nul 2>&1
    if errorlevel 1 (
        echo error: gem not found on PATH or in scoop; 200-scoop-install.cmd should have installed ruby 1>&2
        exit /b 1
    )
)

REM The neovim gem's msgpack dependency builds a C extension, and scoop's
REM ruby ships without the RubyInstaller devkit. msys2 itself comes from
REM scoop (200-scoop-install.cmd); `ridk install 3` drops the ucrt64
REM toolchain into it, and RubyInstaller's rubygems plugin then auto-enables
REM the devkit for native gem builds -- it probes scoop's msys2 location on
REM its own, no MSYS2_PATH needed.
REM Resolved before the block below: %RIDK% inside it expands when the block
REM is parsed, so a set inside the same block would come too late.
set "RIDK=ridk"
call where ridk >nul 2>&1
if errorlevel 1 set "RIDK=%USERPROFILE%\scoop\apps\ruby\current\bin\ridk.cmd"
if not exist "%USERPROFILE%\scoop\apps\msys2\current\ucrt64\bin\gcc.exe" (
    echo debug: installing msys2 ucrt64 toolchain for native gem builds
    call "%RIDK%" install 3
    if errorlevel 1 (
        echo error: ridk install 3 failed 1>&2
        exit /b 1
    )
)

REM ridk enable, explicitly: RubyInstaller's rubygems plugin is supposed to
REM auto-enable the devkit for native builds, but under this scoop layout the
REM build ran devkit-less (mkmf.log showed no ucrt64 on PATH) and msgpack's
REM extension failed. Enabling here puts the toolchain on this script's PATH
REM deterministically; it's cheap and harmless when nothing needs compiling.
call "%RIDK%" enable >nul
if errorlevel 1 (
    echo error: ridk enable failed 1>&2
    exit /b 1
)

for %%g in (ruby-lsp neovim) do call :ensure_gem %%g || exit /b 1
exit /b 0

REM gem list -i is a cheap exact-name presence probe (exit 0 iff installed),
REM so an apply where everything is present touches the network zero times.
:ensure_gem
call "%GEM%" list -i "^%~1$" >nul 2>&1
if not errorlevel 1 (
    echo debug: gem %~1 already installed, skipping
    exit /b 0
)
echo debug: installing gem %~1
call "%GEM%" install %~1
if errorlevel 1 (
    echo error: failed to install gem %~1 1>&2
    exit /b 1
)
exit /b 0
