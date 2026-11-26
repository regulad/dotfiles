@echo off
setlocal

REM Aggressive w32time configuration. This box drifts noticeably between the
REM stock sync intervals -- the default standalone profile polls once a week
REM and refuses to correct anything it considers a "spike". Everything w32time
REM reads from the registry -- the pool.ntp.org peer list, the poll interval,
REM the phase-correction limits, the spike detector -- lives in
REM .chezmoitemplates/registry-system.reg with the repo's other values, and
REM 000-registry imports it before this runs. What is left here is what only
REM sc.exe can do, the service configuration, plus `w32tm /config /update`,
REM which has the running service reload all of the registry's settings.
REM
REM run_onchange_ (not run_once_): the trigger is this file's own contents, so
REM changing anything below re-applies the whole block on the next apply,
REM while an otherwise unchanged apply skips it. run_once_ would key on the
REM content digest with no filename attached and would never re-run a block it
REM had already seen, so reverting a value here would silently leave the old
REM setting in place.
REM
REM sudo is inline (registry-system.reg sets it), so each call below waits for
REM its command and passes the exit code back. The sc calls are still chained
REM into a single `sudo cmd /c` so they cost one elevation prompt instead of
REM four. None of them contain a space or a quote, which is what makes the
REM chaining safe.

REM Outside a domain w32time ships as Manual with a start trigger, and it stops
REM itself once it thinks it is done. Automatic start plus dropping the triggers
REM is what keeps it resident across reboots instead of syncing once and exiting.
REM triggerinfo delete fails once the triggers are already gone, which is the
REM expected state on a re-apply -- with 87 ("The parameter is incorrect") on
REM this build, as `sc qtriggerinfo w32time` confirms there is nothing to delete.
set "ELEV=sc.exe config w32time start= auto"
set "ELEV=%ELEV% & sc.exe triggerinfo w32time delete"

REM If the service dies it stops correcting the clock silently, so restart it
REM rather than leaving it dead until the next reboot.
set "ELEV=%ELEV% & sc.exe failure w32time reset= 86400 actions= restart/60000/restart/60000/restart/60000"

REM Returns 1056 when it is already running, which is harmless and unchecked.
set "ELEV=%ELEV% & sc.exe start w32time"

echo debug: applying w32time service configuration
sudo cmd /c "%ELEV%"

REM /update on its own signals the running service to reload its configuration
REM from the registry: registry-system.reg's peer list and tuning, as imported
REM by 000-registry. (It used to set the peer list here too, through
REM /manualpeerlist and /syncfromflags:manual, which only write the NtpServer
REM and Type values registry-system.reg now carries.)
echo debug: reloading w32time's configuration
sudo w32tm /config /update

REM /rediscover forces the peer list to be re-resolved so the new servers are
REM used immediately instead of at the next poll. Best-effort: a resync can fail
REM simply because the network is not up yet, and the config above still stands.
echo debug: forcing an immediate resync
sudo w32tm /resync /rediscover /nowait

REM Read the results back. The sc chain's exit code is only its last command's
REM (and the triggerinfo/start failures are expected on a re-apply), so the
REM state is what is checked. registry-system.reg's values are 000-registry's.
echo debug: verifying applied configuration

REM findstr, not find, in both checks below. chezmoi is often invoked from
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

sc.exe query w32time | findstr /c:"RUNNING" >nul 2>&1
if errorlevel 1 (
    echo notice: w32time is not running yet; it is set to start automatically 1>&2
)
