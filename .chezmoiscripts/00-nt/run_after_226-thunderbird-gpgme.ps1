# Windows counterpart to 00-linux/run_after_173-thunderbird-flatpak-gpgme-version.sh.tmpl.
# Same underlying bug, different packaging: Thunderbird's "external GnuPG" mode
# dynamically loads libgpgme from the GnuPG install it finds, hardcoding an
# expectation of the GPGME 1.x soname/version. Gpg4win 5.x ships GPGME 2.x
# (libgpgme-45.dll, confirmed present under C:\Program Files\Gpg4win\bin), so
# Thunderbird fails signing/encryption with "GPGME isn't working" until
# mail.openpgp.load_untested_gpgme_version is set to 45 -- Thunderbird's own
# escape hatch for this exact mismatch. Confirmed affecting Windows + Gpg4win
# v5+ specifically:
# https://bugzilla.mozilla.org/show_bug.cgi?id=1967121
# https://etaoinwu.com/en/blog/gpgme-2-workaround-for-thunderbird/
#
# Also sets mail.openpgp.alternative_gpg_path explicitly, pointing at the
# GnuPG core Gpg4win installs (C:\Program Files\GnuPG\bin\gpg.exe) rather than
# leaving Thunderbird to search PATH on its own -- this machine has had more
# than one gpg.exe on PATH at once (Git for Windows' bundled MSYS2 copy, see
# run_after_220-gpg-scoop-unlink.cmd), and pinning the path is cheaper than
# trusting PATH order not to regress again for a consumer that is not scoped
# by this repo's own unlink.
#
# Unlike the Linux Flatpak script, there is no sandbox permission grant half
# to this (172's job on Linux): this is a native Windows install with ordinary
# filesystem access, not a Flatpak sandbox.
#
# The profile directory name is a random per-install salt (e.g.
# uganz4j9.default-release) that cannot be hardcoded, so this resolves it the
# same way Thunderbird itself does: profiles.ini's [InstallXXXXXXXXXXXXXXXX]
# section names the profile actually in use and takes precedence over the
# legacy Default=1 flag on a [ProfileN] section. This machine actually has
# both: a 3sf3kd0u.default profile with no data in it (stale) and the real
# uganz4j9.default-release the Install section points at -- trusting Default=1
# alone would have landed this in the wrong, inert profile. Thunderbird itself
# keeps profiles.ini under %APPDATA% even though profile data (prefs.js
# included) lives under %LOCALAPPDATA% on this build; only the former is read
# here.
#
# No sudo anywhere in this script -- the whole target tree is
# %APPDATA%\Thunderbird, owned by this user -- so like the Flatpak version
# this is a plain run_after_: re-running is free, and re-checking picks up a
# profile that did not exist on a previous apply.
$ThunderbirdRoot = Join-Path $env:APPDATA 'Thunderbird'
$ProfilesIni = Join-Path $ThunderbirdRoot 'profiles.ini'

if (-not (Test-Path -LiteralPath $ProfilesIni)) {
    Write-Host 'debug: no Thunderbird profiles.ini yet, skipping GPGME prefs'
    exit 0
}

$Section = ''
$InstallDefault = $null
$ProfileDefaultPath = $null
$CurrentProfilePath = $null
$CurrentProfileIsDefault = $false

function Flush-ProfileSection {
    if ($script:Section -eq 'profile' -and $script:CurrentProfileIsDefault -and $script:CurrentProfilePath -and -not $script:ProfileDefaultPath) {
        $script:ProfileDefaultPath = $script:CurrentProfilePath
    }
}

foreach ($Line in (Get-Content -LiteralPath $ProfilesIni)) {
    if ($Line -match '^\[Install[0-9A-Fa-f]+\]') {
        Flush-ProfileSection
        $Section = 'install'
        continue
    }
    if ($Line -match '^\[Profile\d+\]') {
        Flush-ProfileSection
        $Section = 'profile'
        $CurrentProfilePath = $null
        $CurrentProfileIsDefault = $false
        continue
    }
    if ($Line -match '^\[') {
        Flush-ProfileSection
        $Section = ''
        continue
    }
    if ($Section -eq 'install' -and -not $InstallDefault -and $Line -match '^Default=(.*)$') {
        $InstallDefault = $Matches[1].Trim()
    }
    if ($Section -eq 'profile') {
        if ($Line -match '^Path=(.*)$') { $CurrentProfilePath = $Matches[1].Trim() }
        if ($Line -match '^Default=1\s*$') { $CurrentProfileIsDefault = $true }
    }
}
Flush-ProfileSection

$RelativeProfile = if ($InstallDefault) { $InstallDefault } else { $ProfileDefaultPath }
if (-not $RelativeProfile) {
    Write-Warning "could not determine the active Thunderbird profile from $ProfilesIni, skipping"
    exit 0
}

$ProfileDir = Join-Path $ThunderbirdRoot $RelativeProfile
if (-not (Test-Path -LiteralPath $ProfileDir)) {
    Write-Warning "$ProfileDir (from $ProfilesIni) does not exist, skipping"
    exit 0
}

# JS string literal inside user.js, so real backslashes need doubling.
$GpgPathJs = 'C:\Program Files\GnuPG\bin\gpg.exe' -replace '\\', '\\'
$UserJsContent = @"
user_pref("mail.openpgp.allow_external_gnupg", true);
user_pref("mail.openpgp.alternative_gpg_path", "$GpgPathJs");
user_pref("mail.openpgp.load_untested_gpgme_version", "45");
"@

$Dest = Join-Path $ProfileDir 'user.js'
if (-not (Test-Path -LiteralPath $Dest) -or (Get-Content -LiteralPath $Dest -Raw) -ne $UserJsContent) {
    # See run_after_225-mailvelope-gpgme.ps1 for why this is WriteAllText and
    # not Set-Content -Encoding utf8NoBOM: that encoding name does not exist
    # in Windows PowerShell 5.1.
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Dest, $UserJsContent, $Utf8NoBom)
    Write-Host "note: wrote $Dest"
}
