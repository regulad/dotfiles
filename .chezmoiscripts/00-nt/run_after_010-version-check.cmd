@echo off
setlocal enabledelayedexpansion

REM Check Windows version
for /f "tokens=3" %%v in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul') do set BUILD=%%v

REM The floor is build 26100: Windows 11 24H2, and Windows Server 2025, which
REM shares its codebase and is what GitHub's windows-2025 runners run (see
REM .github/workflows/windows-apply.yml). 25H2 (26200) is the same servicing
REM branch with more features switched on, so it passes too.
if %BUILD% LSS 26100 (
    echo error: Windows build must be ^>= 26100 ^(Windows 11 24H2 / Server 2025^), found %BUILD% 1>&2
    exit /b 1
)

REM Check for winget
call where winget >nul 2>&1
if %errorLevel% neq 0 (
    echo error: winget is not available 1>&2
    exit /b 1
)
