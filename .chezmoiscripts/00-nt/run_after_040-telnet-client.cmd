@echo off
setlocal

REM telnet on Windows is Microsoft's own client: the TelnetClient optional
REM feature, which puts telnet.exe in System32. It replaced scoop's `telnet`,
REM which was GNU inetutils 1.7 from 2009 on MinGW's abandoned MSYS1 runtime,
REM downloaded from SourceForge; 206-scoop-telnet-remove uninstalls that.
REM
REM Every apply, but the common case costs nothing and needs no elevation. The
REM feature's state can only be read elevated, so the file it installs is the
REM test, and sudo -- one UAC prompt, once per machine -- only runs when it is
REM missing. On a client SKU and on Server alike the payload ships with the
REM OS, so enabling needs no download and, for this feature, no restart.
if exist "%SystemRoot%\System32\telnet.exe" (
    echo debug: Windows Telnet Client already enabled
    exit /b 0
)

REM Through the DISM PowerShell module, as 035-sshd-user-session adds its
REM Windows capability, not dism.exe: under sudo from an apply, dism.exe got as
REM far as opening its image session and then quit with error 31 ("An error
REM occurred while creating the log file"). sudo is inline (registry-system.reg),
REM so the exit code comes back; -ErrorAction Stop makes a failure a non-zero one.
echo notice: enabling the Windows Telnet Client optional feature
call sudo powershell -NoProfile -NonInteractive -Command "Enable-WindowsOptionalFeature -Online -FeatureName TelnetClient -NoRestart -ErrorAction Stop | Out-Null"
if errorlevel 1 (
    echo error: enabling the Telnet Client failed -- was the elevation prompt declined? 1>&2
    exit /b 1
)

if not exist "%SystemRoot%\System32\telnet.exe" (
    echo error: dism reported success but %SystemRoot%\System32\telnet.exe is missing 1>&2
    exit /b 1
)
echo notice: Windows Telnet Client enabled
