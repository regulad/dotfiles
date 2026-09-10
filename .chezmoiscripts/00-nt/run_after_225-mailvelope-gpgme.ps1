# Registers Gpg4win's bundled gpgme-json.exe as a native messaging host so
# Mailvelope (and any other WebExtension using gpgme.js) can reach it. Chrome,
# Edge and Firefox each discover native messaging hosts the same way: a
# per-browser registry key under NativeMessagingHosts\gpgmejson whose default
# value is the path to a manifest JSON file naming the host binary and the
# extension IDs allowed to talk to it.
#
# Gpg4win ships gpgme-chrome.json/gpgme-edge.json/gpgme-mozilla.json next to
# gpgme-json.exe in its own bin directory, and presumably a Kleopatra wizard is
# meant to both copy those into place and write the registry keys -- but nothing
# in this repo drives that wizard, it is GUI-only, and those three files
# disappeared from Gpg4win\bin at some point in this machine's history (not
# reproduced here; plausibly a Windows Installer component collision with the
# separate standalone GnuPG package once installed alongside Gpg4win). Rather
# than depend on the wizard or on files that have already proven to vanish,
# this generates the manifests itself from Mailvelope's own published schema
# (https://github.com/mailvelope/mailvelope/wiki/Creating-the-app-manifest-file-on-macOS-and-Linux)
# into a location this repo controls, and points the registry at that.
#
# HKCU, not HKLM: native messaging hosts are a per-user registration (every
# other host already on this machine -- Bitwarden, the Claude browser
# extensions, OneDrive -- is HKCU-only), so this needs no elevation.
#
# Runs every apply, not run_once: self-healing against exactly the kind of
# silent disappearance that motivated writing this in the first place, and
# against Gpg4win ever moving where it installs gpgme-json.exe.
$Gpgme = 'C:\Program Files\Gpg4win\bin\gpgme-json.exe'
$ManifestDir = Join-Path $env:LOCALAPPDATA 'gpgme'

if (-not (Test-Path -LiteralPath $Gpgme)) {
    Write-Host 'debug: gpgme-json.exe not found under Gpg4win, skipping native messaging setup'
    exit 0
}

New-Item -ItemType Directory -Force -Path $ManifestDir | Out-Null

# Forward slashes rather than backslashes in the manifest's path field: valid
# on Windows, and sidesteps ConvertTo-Json's backslash-escaping entirely rather
# than relying on it being correct.
$GpgmePathJson = $Gpgme -replace '\\', '/'

# [System.IO.File]::WriteAllText rather than Set-Content -Encoding utf8NoBOM:
# that encoding name is a PowerShell 6+ addition and this runs under Windows
# PowerShell 5.1 (chezmoi's default .ps1 interpreter on Windows), where it is
# an unrecognized enum value and the parameter bind fails outright.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-ManifestIfChanged {
    param([string]$Path, [hashtable]$Content)
    $Json = $Content | ConvertTo-Json -Depth 4
    if ((Test-Path -LiteralPath $Path) -and ((Get-Content -LiteralPath $Path -Raw) -eq $Json)) {
        return
    }
    [System.IO.File]::WriteAllText($Path, $Json, $Utf8NoBom)
    Write-Host "debug: wrote $Path"
}

# Mailvelope's published Chrome Web Store / Edge Add-ons / Firefox (jetpack)
# extension IDs -- see the wiki page linked above. Brave is not separately
# registered: per that same page, Brave reads the Chrome registry path, so the
# Chrome registration below covers it too.
$ChromeManifest = Join-Path $ManifestDir 'gpgme-chrome.json'
Write-ManifestIfChanged -Path $ChromeManifest -Content @{
    name            = 'gpgmejson'
    description     = 'JavaScript binding for GnuPG'
    path            = $GpgmePathJson
    type            = 'stdio'
    allowed_origins = @('chrome-extension://kajibbejlbohfaggdiogboambcijhkke/')
}

$EdgeManifest = Join-Path $ManifestDir 'gpgme-edge.json'
Write-ManifestIfChanged -Path $EdgeManifest -Content @{
    name            = 'gpgmejson'
    description     = 'JavaScript binding for GnuPG'
    path            = $GpgmePathJson
    type            = 'stdio'
    allowed_origins = @('chrome-extension://dgcbddhdhjppfdfjpciagmmibadmoapc/')
}

$MozillaManifest = Join-Path $ManifestDir 'gpgme-mozilla.json'
Write-ManifestIfChanged -Path $MozillaManifest -Content @{
    name               = 'gpgmejson'
    description        = 'JavaScript binding for GnuPG'
    path               = $GpgmePathJson
    type               = 'stdio'
    allowed_extensions = @('jid1-AQqSMBYb0a8ADg@jetpack')
}

$Registrations = @(
    @{ Hive = 'Software\Google\Chrome\NativeMessagingHosts'; Manifest = $ChromeManifest }
    @{ Hive = 'Software\Microsoft\Edge\NativeMessagingHosts'; Manifest = $EdgeManifest }
    @{ Hive = 'Software\Mozilla\NativeMessagingHosts'; Manifest = $MozillaManifest }
)
foreach ($Reg in $Registrations) {
    $KeyPath = "HKCU:\$($Reg.Hive)\gpgmejson"
    New-Item -Path $KeyPath -Force | Out-Null
    Set-Item -LiteralPath $KeyPath -Value $Reg.Manifest
}
