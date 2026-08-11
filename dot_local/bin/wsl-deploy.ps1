<#
.SYNOPSIS
    Deploy the newest regulad/dotfiles WSL image and drop into its OOBE.

.DESCRIPTION
    Finds the most recent non-expired wsl-<flavor>-<arch> build artifact,
    downloads it, replaces any existing regulad-<flavor> instance, and imports
    it. The first interactive shell runs /etc/oobe.sh, which pulls the
    Bitwarden API credentials off this machine's own .secrets/.bwrc and runs
    the privileged chezmoi apply.

    The tarballs live as GitHub Actions artifacts rather than release assets
    because they are ~5 GB and a release asset is capped at 2 GB. Artifacts
    expire (currently 14 days), so this deliberately skips expired ones rather
    than failing on a dead download link.

.NOTES
    Reachable as `wsl-deploy` in cmd via the doskey macro in .doskey.mac.
    ~/.local/bin is only put on PATH by .commonprofile, which is POSIX shells
    only, so the macro invokes it by full path the same way c3/t3 do. Note
    that .doskey.mac cannot carry a comment saying so -- doskey macro files
    have no comment syntax, and REM is not one.

.EXAMPLE
    wsl-deploy                 # newest ubuntu image for this architecture
    wsl-deploy fedora
    wsl-deploy.ps1 -Flavor fedora -Force
#>
[CmdletBinding()]
param(
    # Positional so `wsl-deploy fedora` works through the doskey macro, which
    # forwards $* to `pwsh -File`.
    [Parameter(Position = 0)]
    [ValidateSet('fedora', 'ubuntu')]
    [string]$Flavor = 'ubuntu',

    [string]$Repo = 'regulad/dotfiles',

    # Replace an existing instance without asking. Destroys it -- there is no
    # undo, and anything not committed inside that instance is gone.
    [switch]$Force,

    # Import but do not launch. OOBE will instead run on your next
    # `wsl -d regulad-<flavor>`, since it triggers on the first interactive
    # shell rather than at install time.
    [switch]$NoLaunch,

    # Keep the downloaded .wsl. Off by default: import copies everything into
    # the instance's VHD, so the tarball is ~5 GB of dead weight afterwards.
    [switch]$KeepDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# wsl.exe emits UTF-16LE by default, which lands in PowerShell as strings full
# of NULs that no comparison will match. WSL_UTF8 is the supported way to get
# parseable output; without it the "is this distro already installed" check
# silently never matches and this would happily install a second copy.
$env:WSL_UTF8 = '1'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }

function Assert-NativeSuccess {
    param([string]$What)
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}

# --- preflight -------------------------------------------------------------

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "gh is not on PATH. It comes from scoop; see .chezmoiscripts/00-nt/run_once_after_200-scoop-install.cmd"
}

gh auth status 2>&1 | Out-Null
Assert-NativeSuccess 'gh auth status'

wsl.exe --version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "WSL is not installed. Run .chezmoiscripts/00-nt/run_once_after_110-wsl-install.cmd, or 'wsl --install --no-distribution'."
}

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { throw "unsupported processor architecture '$($env:PROCESSOR_ARCHITECTURE)'; only amd64 and arm64 images are built" }
}

$artifactName = "wsl-$Flavor-$arch"
$distroName   = "regulad-$Flavor"
$installPath  = Join-Path $env:LOCALAPPDATA "wsl\$distroName"

Write-Step "deploying $artifactName as '$distroName'"

# --- locate the newest usable artifact -------------------------------------

Write-Step "looking up the newest $artifactName build"

# The artifacts API returns newest first and reports expiry, so this needs one
# request -- as opposed to walking `gh run list` and querying each run's
# artifacts until one has the right name.
$artifactsJson = gh api "repos/$Repo/actions/artifacts?name=$artifactName&per_page=20" 2>&1
Assert-NativeSuccess "gh api artifacts?name=$artifactName"

$artifact = ($artifactsJson | ConvertFrom-Json).artifacts |
    Where-Object { -not $_.expired } |
    Sort-Object { [datetime]$_.created_at } -Descending |
    Select-Object -First 1

if (-not $artifact) {
    throw "no unexpired '$artifactName' artifact found in $Repo. Artifacts expire after 14 days; push to master or re-run the Docker workflow to produce a fresh one."
}

$sizeGb = [math]::Round($artifact.size_in_bytes / 1GB, 2)
Write-Note "run $($artifact.workflow_run.id), built $($artifact.created_at), $sizeGb GB"

# --- check there is room ---------------------------------------------------

# The tarball is downloaded and then expanded into a VHD, so both exist at
# once. Roughly 4x the compressed size covers the download, the zip gh wraps
# it in, and the expanded filesystem.
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
$needGb = [math]::Round($sizeGb * 4, 2)
if ($freeGb -lt $needGb) {
    throw "need roughly $needGb GB free on C: for the download and import, but only $freeGb GB is available"
}

# --- replace any existing instance -----------------------------------------

$existing = (wsl.exe --list --quiet) -contains $distroName
if ($existing) {
    Write-Host ""
    Write-Host "  '$distroName' is already installed." -ForegroundColor Yellow
    Write-Host "  Replacing it UNREGISTERS it: its disk, and anything in it that" -ForegroundColor Yellow
    Write-Host "  is not pushed somewhere, is destroyed. There is no undo." -ForegroundColor Yellow
    Write-Host ""

    if (-not $Force) {
        $reply = Read-Host "  Replace '$distroName'? [y/N]"
        if ($reply -notmatch '^[Yy]') {
            Write-Step 'left the existing instance alone; nothing was changed.'
            return
        }
    }

    Write-Step "unregistering $distroName"
    wsl.exe --unregister $distroName
    Assert-NativeSuccess "wsl --unregister $distroName"
}

# --- download --------------------------------------------------------------

$downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) "wsl-deploy-$Flavor-$arch"
if (Test-Path $downloadDir) { Remove-Item -Recurse -Force $downloadDir }
New-Item -ItemType Directory -Path $downloadDir | Out-Null

try {
    Write-Step "downloading $sizeGb GB (this takes a while)"
    gh run download $artifact.workflow_run.id --repo $Repo --name $artifactName --dir $downloadDir
    Assert-NativeSuccess 'gh run download'

    $tarball = Get-ChildItem -Path $downloadDir -Filter '*.wsl' -File | Select-Object -First 1
    if (-not $tarball) {
        throw "no .wsl file inside artifact $artifactName"
    }

    # --- import ------------------------------------------------------------

    Write-Step "importing as '$distroName' at $installPath"
    $installArgs = @(
        '--install'
        '--from-file', $tarball.FullName
        '--name', $distroName
        '--location', $installPath
    )
    # Without --no-launch, wsl opens an interactive shell right here, which is
    # what triggers oobe.command. OOBE does not fire for a non-interactive
    # `wsl -d <name> -- <cmd>`.
    if ($NoLaunch) { $installArgs += '--no-launch' }

    wsl.exe @installArgs
    Assert-NativeSuccess 'wsl --install --from-file'
}
finally {
    if (-not $KeepDownload -and (Test-Path $downloadDir)) {
        Write-Note "cleaning up $downloadDir"
        Remove-Item -Recurse -Force $downloadDir -ErrorAction SilentlyContinue
    }
}

# --- what happens next -----------------------------------------------------

Write-Host ""
if ($NoLaunch) {
    Write-Step "installed. Run 'wsl -d $distroName' to start the first-run setup."
} else {
    Write-Step "installed."
}
Write-Note "The first interactive shell runs /etc/oobe.sh, which finds your"
Write-Note "Bitwarden API credentials at C:\Users\<you>\.secrets\.bwrc and runs"
Write-Note "the privileged apply. It will ask for your vault master password."
Write-Note ""
Write-Note "To re-run it later:  wsl -d $distroName -u root -- /etc/oobe.sh"
Write-Note "To remove it:        wsl --unregister $distroName"
