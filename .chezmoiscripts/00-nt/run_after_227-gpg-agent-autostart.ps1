# Windows counterpart to the Linux `systemctl --user enable --now
# gpg-agent.socket` fix (run_after_150-user-services.sh.tmpl): hands
# gpg-agent's startup to a login-time supervisor instead of leaving it to
# gpg's own opportunistic autospawn-on-first-use.
#
# Confirmed the failure mode this fixes: after a reboot, gpg-agent.exe was not
# running at all until something (Kleopatra, a manual `gpg` invocation, ...)
# happened to trigger autospawn -- and if the first thing to want it is
# Thunderbird or a browser-launched gpgme-json.exe, that first attempt is
# exactly the "doesn't see the key" failure this whole chain of fixes has been
# chasing, just recurring on every fresh boot rather than being permanently
# fixed. There is no gpg-agent.socket/systemd-user-instance equivalent on
# Windows to enable; a Scheduled Task at logon is the closest analogue.
#
# LogonType Interactive, not S4U/Password: pinentry needs to show a real GUI
# dialog for passphrase prompts, which requires binding the task to the actual
# desktop logon session -- same reasoning as
# run_onchange_after_035-sshd-user-session.ps1.tmpl's Interactive requirement,
# different underlying reason (there it was drive-letter visibility).
#
# RunLevel Limited, not elevated: gpg-agent has no reason to run as admin, and
# an elevated token is a second, different logon view from the one pinentry
# and every calling app (Thunderbird, browsers) actually run under.
#
# Unlike the sshd task, this one is not itself the long-running process --
# `gpgconf --launch gpg-agent` starts a detached gpg-agent.exe and returns
# immediately, so there is no task process tree to reap on re-registration,
# and `gpgconf --launch` is itself idempotent (a no-op if the agent is already
# running), so re-running this at every logon or every apply is free.
#
# Runs every apply, not run_once: self-healing if the task is ever removed or
# its definition drifts, matching every other script in this GPG cluster.
$TaskName = 'chezmoi-gpg-agent-autostart'
$Gpgconf = 'C:\Program Files\GnuPG\bin\gpgconf.exe'
$Conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'

if (-not (Test-Path -LiteralPath $Gpgconf)) {
    Write-Host 'debug: gpgconf.exe not present, skipping gpg-agent autostart task'
    exit 0
}

# Torn down and rebuilt rather than patched in place, so the registered task
# always matches this file exactly -- same approach as the sshd task.
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# conhost --headless avoids a console window flashing on screen at every
# logon; -WindowStyle Hidden alone would not, since the window is still
# created and then hidden.
$Action = New-ScheduledTaskAction -Execute $Conhost `
    -Argument "--headless `"$Gpgconf`" --launch gpg-agent"

$Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
    -Principal $Principal -Settings $Settings `
    -Description 'Launches gpg-agent in the interactive desktop session at logon, so pinentry can show its UI and callers (Thunderbird, browsers via gpgme-json) do not have to be the ones to trigger autospawn. Managed by chezmoi.' `
    -Force | Out-Null

# Read back the two silent-failure settings rather than trusting that
# Register-ScheduledTask honoured them -- same defensive check as the sshd
# task, for the same reason (both fail with no error and no obvious symptom
# beyond "pinentry never appears").
$Registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $Registered) {
    Write-Error "scheduled task '$TaskName' was not registered"
    exit 1
}
if ("$($Registered.Principal.RunLevel)" -ne 'Limited') {
    Write-Error "scheduled task '$TaskName' registered with RunLevel $($Registered.Principal.RunLevel), expected Limited."
    exit 1
}
if ("$($Registered.Principal.LogonType)" -ne 'Interactive') {
    Write-Error "scheduled task '$TaskName' registered with LogonType $($Registered.Principal.LogonType), expected Interactive."
    exit 1
}

# Also run it now, so this apply itself does not require a reboot/relogon to
# take effect -- harmless and near-instant if gpg-agent is already running.
Start-ScheduledTask -TaskName $TaskName
