# Thunderbird's external-GnuPG mode dynamically loads libgpgme via the system
# DLL search path, not via the HKLM\SOFTWARE\GnuPG\Install Directory registry
# key GPGME itself uses internally to locate gpg.exe/gpgconf.exe (Mozilla
# support: "Thunderbird must be able to find GPGME in the system library
# search path", https://support.mozilla.org/en-US/questions/1441288).
#
# Only C:\Program Files\Gpg4win\..\GnuPG\bin (= C:\Program Files\GnuPG\bin --
# gpg.exe/gpgconf.exe/gpg-agent.exe, no gpgme dll) is on PATH, added by the
# GnuPG installer. C:\Program Files\Gpg4win\bin, where libgpgme-45.dll
# actually lives, is on PATH nowhere on this machine (checked user and
# machine scope). Kleopatra never surfaced this: kleopatra.exe and
# libgpgme-45.dll live in the same directory, and Windows searches an EXE's
# own directory before PATH. Thunderbird, in a completely different
# directory (C:\Program Files\Mozilla Thunderbird), has no such shortcut and
# needs PATH.
#
# [Environment]::SetEnvironmentVariable rather than a raw registry write: it
# also broadcasts WM_SETTINGCHANGE, which is what lets Explorer pick up the
# new PATH for anything launched from the Start menu/taskbar afterwards
# without a full log off. A raw registry Set-ItemProperty would silently only
# apply to processes started after the *next* logon. Still requires whatever
# is meant to see this (Thunderbird) to be a freshly started process, not one
# already running from before this change -- environment is inherited at
# process creation, not re-read live.
#
# User scope, not machine: avoids needing elevation, and DLL search path
# resolution does not care whether PATH came from the user or machine scope --
# both are merged into the process environment at launch either way.
#
# Runs every apply, not run_once: self-healing if Gpg4win is ever reinstalled
# to a path that drops this, or if something else strips it from PATH the way
# the gpgme-chrome.json/gpgme-edge.json/gpgme-mozilla.json manifests
# disappeared (see run_after_225-mailvelope-gpgme.ps1).
$GpgmeDir = 'C:\Program Files\Gpg4win\bin'

if (-not (Test-Path -LiteralPath $GpgmeDir)) {
    Write-Host 'debug: Gpg4win\bin not present, skipping GPGME PATH fixup'
    exit 0
}

$CurrentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$Entries = @()
if ($CurrentPath) { $Entries = $CurrentPath -split ';' | Where-Object { $_ -ne '' } }

$AlreadyPresent = $Entries | Where-Object { $_.TrimEnd('\') -ieq $GpgmeDir.TrimEnd('\') }
if ($AlreadyPresent) {
    Write-Host 'debug: Gpg4win\bin already on user PATH'
    exit 0
}

$NewPath = ($Entries + $GpgmeDir) -join ';'
[Environment]::SetEnvironmentVariable('Path', $NewPath, 'User')
Write-Host "note: added $GpgmeDir to the user PATH -- restart apps that need to pick it up (Thunderbird included)"
