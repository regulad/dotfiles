@echo off
setlocal

REM Aggressive w32time configuration. This box drifts noticeably between the
REM stock sync intervals -- the default standalone profile polls once a week
REM and refuses to correct anything it considers a "spike" -- so the poll
REM interval, the phase-correction limits and the spike detector are all
REM retuned below to keep the clock pinned instead of merely close.
REM
REM run_onchange_ (not run_once_): the trigger is this file's own contents, so
REM retuning any value below re-applies the whole block on the next apply,
REM while an otherwise unchanged apply skips it. run_once_ would key on the
REM content digest with no filename attached and would never re-run a block it
REM had already seen, so reverting a value here would silently leave the old
REM setting in place.
REM
REM Note: w32time cannot learn its NTP servers from DHCP. There is no Windows
REM equivalent of dhclient/systemd-timesyncd consuming DHCP option 42
REM (NTP Servers) or the legacy option 4 (Time Server): the Windows DHCP
REM client neither requests nor surfaces them, and w32time has no hook to read
REM them if it did. Outside a domain -- where w32time instead discovers a
REM time source through the NT5DS/domain hierarchy -- the peer list has to be
REM static, which is why it is hardcoded below rather than left to the
REM network to supply.
REM
REM Two things about sudo on this machine shape everything below. It is pinned
REM to Force New Window mode by policy -- `sudo --inline` is refused outright
REM with "You cannot run in a mode higher than Force New Window mode on this
REM machine" -- and in that mode:
REM
REM   1. The child's exit code is not propagated. `sudo cmd /c exit 42` returns
REM      0, so `if errorlevel 1` after any sudo call is dead code that silently
REM      passes. The state checks at the end of this script are the real error
REM      detection; they read back what was written rather than trusting sudo.
REM   2. `reg import <file>` does not work through it. It elevates and returns
REM      success while importing nothing, which is why the values below are
REM      written with `reg add` (as in 000-policy.cmd) rather than as a .reg
REM      file, despite reg add costing one command per value.
REM
REM The reg adds and sc calls are therefore chained into a single `sudo cmd /c`
REM so the whole batch costs one elevation prompt instead of eighteen. None of
REM them contain a space or a quote, which is what makes the chaining safe --
REM the w32tm call further down has both, so it stays its own sudo.

set "W32CFG=HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Config"
set "W32NTP=HKLM\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient"
set "RA=reg add"

REM MinPollInterval/MaxPollInterval are log2 seconds: 6 = 64s, 10 = 1024s. The
REM standalone defaults are 10/15, i.e. up to 9 hours between polls.
set "ELEV=%RA% %W32CFG% /v MinPollInterval /t REG_DWORD /d 6 /f"
set "ELEV=%ELEV% & %RA% %W32CFG% /v MaxPollInterval /t REG_DWORD /d 10 /f"

REM Clock ticks between phase corrections. Standalone default is 360000 (~1
REM hour); 100 applies the accumulated correction roughly every second.
set "ELEV=%ELEV% & %RA% %W32CFG% /v UpdateInterval /t REG_DWORD /d 100 /f"

REM Slew rate divisor -- 1 is the fastest correction w32time will apply.
set "ELEV=%ELEV% & %RA% %W32CFG% /v PhaseCorrectRate /t REG_DWORD /d 1 /f"

REM Max offset (seconds) w32time will accept and correct. 0xffffffff means
REM "always correct", however far off the local clock has wandered; the default
REM 54000 silently gives up past 15 hours and leaves the clock wrong.
set "ELEV=%ELEV% & %RA% %W32CFG% /v MaxPosPhaseCorrection /t REG_DWORD /d 0xffffffff /f"
set "ELEV=%ELEV% & %RA% %W32CFG% /v MaxNegPhaseCorrection /t REG_DWORD /d 0xffffffff /f"

REM Offset (seconds) past which the clock is stepped rather than slewed. 1
REM trades a monotonic clock for actually being on time; slewing a large offset
REM at the default 300s threshold can take hours to converge.
set "ELEV=%ELEV% & %RA% %W32CFG% /v MaxAllowedPhaseOffset /t REG_DWORD /d 1 /f"

REM Seconds a suspiciously large sample is watched before it is believed. The
REM default 900 is 15 minutes of knowingly-wrong clock.
set "ELEV=%ELEV% & %RA% %W32CFG% /v SpikeWatchPeriod /t REG_DWORD /d 90 /f"

REM Samples accepted without spike checking after a sync -- shortened so a
REM genuine jump is not held off for five consecutive polls.
set "ELEV=%ELEV% & %RA% %W32CFG% /v HoldPeriod /t REG_DWORD /d 2 /f"

REM 1 = special-source events, 2 = time-jump events, 3 = both. Time jumps are
REM the only record left that a correction happened at all.
set "ELEV=%ELEV% & %RA% %W32CFG% /v EventLogFlags /t REG_DWORD /d 3 /f"

set "ELEV=%ELEV% & %RA% %W32NTP% /v Enabled /t REG_DWORD /d 1 /f"

REM Poll interval in seconds for peers flagged 0x1 (SpecialInterval), which the
REM peer list below is. 900 = every 15 minutes; pool.ntp.org's terms ask that
REM clients not poll more often than necessary, and 15 minutes is well inside
REM what the pool considers polite for a single host.
set "ELEV=%ELEV% & %RA% %W32NTP% /v SpecialPollInterval /t REG_DWORD /d 900 /f"

REM Minutes to wait before re-resolving a peer that failed to answer, and how
REM many times to back off. The defaults (15 / 7) mean a transient DNS or
REM network failure can cost most of a day of no syncing at all.
set "ELEV=%ELEV% & %RA% %W32NTP% /v ResolvePeerBackoffMinutes /t REG_DWORD /d 1 /f"
set "ELEV=%ELEV% & %RA% %W32NTP% /v ResolvePeerBackoffMaxTimes /t REG_DWORD /d 3 /f"

REM Outside a domain w32time ships as Manual with a start trigger, and it stops
REM itself once it thinks it is done. Automatic start plus dropping the triggers
REM is what keeps it resident across reboots instead of syncing once and exiting.
REM triggerinfo delete fails with 1168 (element not found) once the triggers are
REM already gone, which is the expected state on a re-apply.
set "ELEV=%ELEV% & sc.exe config w32time start= auto"
set "ELEV=%ELEV% & sc.exe triggerinfo w32time delete"

REM If the service dies it stops correcting the clock silently, so restart it
REM rather than leaving it dead until the next reboot.
set "ELEV=%ELEV% & sc.exe failure w32time reset= 86400 actions= restart/60000/restart/60000/restart/60000"

REM Returns 1056 when it is already running, which is harmless and unchecked.
set "ELEV=%ELEV% & sc.exe start w32time"

echo debug: applying w32time tuning and service configuration
sudo cmd /c "%ELEV%"

REM The pool rather than time.windows.com: Microsoft's server is a single
REM anycast endpoint polled by every Windows machine on earth and is routinely
REM seconds off, while the pool hands out four independent servers that w32time
REM can compare against each other and discard outliers from.
REM
REM 0x9 = 0x1 SpecialInterval plus 0x8 Client, so SpecialPollInterval above is
REM the poll rate. Dropping 0x1 would hand the schedule back to
REM Min/MaxPollInterval. syncfromflags:manual pins w32time to this list instead
REM of the domain hierarchy, and /update signals the running service to reload
REM everything set above.
echo debug: pointing w32time at pool.ntp.org
sudo w32tm /config /manualpeerlist:"0.pool.ntp.org,0x9 1.pool.ntp.org,0x9 2.pool.ntp.org,0x9 3.pool.ntp.org,0x9" /syncfromflags:manual /update

REM /rediscover forces the peer list to be re-resolved so the new servers are
REM used immediately instead of at the next poll. Best-effort: a resync can fail
REM simply because the network is not up yet, and the config above still stands.
echo debug: forcing an immediate resync
sudo w32tm /resync /rediscover /nowait

REM Read the settings back. sudo reports success unconditionally (see above), so
REM without this the script cannot tell an applied config from a declined UAC
REM prompt. One value per elevated batch is enough to prove that batch ran.
echo debug: verifying applied configuration

for /f "tokens=3" %%v in ('reg query "%W32CFG%" /v MaxPollInterval 2^>nul') do set "CHECK_POLL=%%v"
if not "%CHECK_POLL%"=="0xa" (
    echo error: w32time registry tuning did not apply -- MaxPollInterval is 1>&2
    echo error: "%CHECK_POLL%", expected 0xa. Was the elevation prompt declined? 1>&2
    exit /b 1
)

for /f "tokens=3" %%v in ('reg query "%W32NTP%" /v SpecialPollInterval 2^>nul') do set "CHECK_SPI=%%v"
if not "%CHECK_SPI%"=="0x384" (
    echo error: w32time NtpClient tuning did not apply -- SpecialPollInterval 1>&2
    echo error: is "%CHECK_SPI%", expected 0x384. 1>&2
    exit /b 1
)

REM findstr, not find, in all three checks below. chezmoi is often invoked from
REM Git Bash here, and the PATH the script inherits from it puts the scoop Git
REM installation's Unix find.exe (usr/bin/find) ahead of C:\Windows\System32,
REM so `| find "..."` runs GNU find against a nonexistent path and reports a
REM false failure. Git ships no findstr, so findstr always resolves to the
REM Windows one regardless of which shell launched the apply.
sc.exe qc w32time | findstr /c:"AUTO_START" >nul 2>&1
if errorlevel 1 (
    echo error: w32time is not set to start automatically 1>&2
    exit /b 1
)

reg query "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" /v NtpServer 2>nul | findstr /c:"pool.ntp.org" >nul 2>&1
if errorlevel 1 (
    echo error: w32time peer list was not set to the ntp.org pool 1>&2
    exit /b 1
)

sc.exe query w32time | findstr /c:"RUNNING" >nul 2>&1
if errorlevel 1 (
    echo note: w32time is not running yet; it is set to start automatically 1>&2
)
