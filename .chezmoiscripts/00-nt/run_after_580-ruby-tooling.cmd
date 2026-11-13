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
REM
REM gem and ridk are resolved to full paths, never left as bare names: their
REM .cmd wrappers find ruby.exe through %~dp0, and cmd gets %~dp0 wrong for a
REM batch file started by a quoted bare name found on PATH. `call "ridk"`
REM from the home directory, where chezmoi runs scripts, looked for
REM "C:\Users\<user>\ruby" and failed; `call "%GEM%"` with GEM=gem did the same.
set "GEM="
for /f "delims=" %%i in ('where gem.cmd 2^>nul') do if not defined GEM set "GEM=%%i"
if not defined GEM set "GEM=%USERPROFILE%\scoop\apps\ruby\current\bin\gem.cmd"
if not exist "%GEM%" (
    echo error: gem not found on PATH or in scoop; 200-scoop-install.cmd should have installed ruby 1>&2
    exit /b 1
)

REM The neovim gem's msgpack dependency builds a C extension, and scoop's
REM ruby ships without the RubyInstaller devkit. msys2 itself comes from
REM scoop (200-scoop-install.cmd); `ridk install 3` drops the ucrt64
REM toolchain into it, and RubyInstaller's rubygems plugin then auto-enables
REM the devkit for native gem builds -- it probes scoop's msys2 location on
REM its own, no MSYS2_PATH needed.
REM Resolved before the block below: %RIDK% inside it expands when the block
REM is parsed, so a set inside the same block would come too late.
set "RIDK="
for /f "delims=" %%i in ('where ridk.cmd 2^>nul') do if not defined RIDK set "RIDK=%%i"
if not defined RIDK set "RIDK=%USERPROFILE%\scoop\apps\ruby\current\bin\ridk.cmd"

REM ARM64 is different on two counts. RubyInstaller's ARM64 Ruby (which scoop
REM installs there, like chezmoi) builds with MSYS2's clangarm64 environment,
REM not ucrt64, so its toolchain is clang, in clangarm64\bin. And `ridk install
REM 3` cannot install it in RubyInstaller 4.0.9-1: it asks pacman for
REM mingw-w64-clang-aarch64-gcc-libs, which clangarm64 does not have ("target
REM not found"; windows-apply on windows-11-arm, 2026-11-06 to 11-08, after
REM which 570 failed first). RubyInstaller fixed its list on 2026-10-30
REM (oneclick/rubyinstaller2 17088a0, "Remove gcc-libs from devkit packages":
REM gcc and gcc-libs became mingw-w64-cc), after the 4.0.9-1 release. Until a
REM release carries it, ARM64 installs that same corrected list itself, with
REM pacman inside ridk's MSYS2; once one does, this can go back to `ridk
REM install 3` with the clang.exe test below.
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" goto :toolchain_arm64
if not exist "%USERPROFILE%\scoop\apps\msys2\current\ucrt64\bin\gcc.exe" (
    echo debug: installing msys2 ucrt64 toolchain for native gem builds
    call "%RIDK%" install 3
    if errorlevel 1 (
        echo error: ridk install 3 failed 1>&2
        exit /b 1
    )
)
goto :toolchain_done

:toolchain_arm64
if exist "%USERPROFILE%\scoop\apps\msys2\current\clangarm64\bin\clang.exe" goto :toolchain_done
echo debug: installing msys2 clangarm64 toolchain for native gem builds
set "P=mingw-w64-clang-aarch64"
call "%RIDK%" exec pacman -S --needed --noconfirm autoconf autogen automake-wrapper diffutils file gawk grep libtool m4 make patch sed texinfo texinfo-tex wget %P%-binutils %P%-crt-git %P%-cc %P%-headers-git %P%-libwinpthread-git %P%-winpthreads-git pkgconf %P%-libmangle-git %P%-make %P%-pkgconf %P%-tools-git
if errorlevel 1 (
    echo error: installing the clangarm64 toolchain failed 1>&2
    exit /b 1
)
if not exist "%USERPROFILE%\scoop\apps\msys2\current\clangarm64\bin\clang.exe" (
    echo error: pacman finished but clangarm64\bin\clang.exe is missing 1>&2
    exit /b 1
)

:toolchain_done

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
