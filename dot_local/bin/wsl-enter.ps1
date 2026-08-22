<#
.SYNOPSIS
    Open a shell in a deployed regulad WSL instance, in the caller's directory.

.DESCRIPTION
    The companion to wsl-deploy.ps1: that one installs regulad-<flavor>, this
    one drops you into it. The working directory follows you in, so
    `wsl-enter` from D:\repositories\foo lands in /mnt/d/repositories/foo
    rather than in $HOME.

    Deliberately does no installing, downloading, or unregistering. If the
    instance is not there, this says so and points at wsl-deploy rather than
    quietly producing one.

.NOTES
    Reachable as `wsl-enter` in cmd via the doskey macro in .doskey.mac, which
    invokes it by full path for the same reason wsl-deploy does: ~/.local/bin
    is only put on PATH by .commonprofile, which is POSIX shells only.

.EXAMPLE
    wsl-enter                  # ubuntu, in the current directory
    wsl-enter fedora
    wsl-enter -Flavor ubuntu -NoCd
#>
[CmdletBinding()]
param(
    # Positional so `wsl-enter fedora` works through the doskey macro, which
    # forwards $* to `pwsh -File`. Matches wsl-deploy's signature.
    [Parameter(Position = 0)]
    [ValidateSet('fedora', 'ubuntu')]
    [string]$Flavor = 'ubuntu',

    # Start in the instance's home directory instead of translating the
    # current one. This is also what you get automatically when the current
    # directory is not something WSL can see; see Resolve-StartDirectory.
    #
    # Not named -Home: that would shadow PowerShell's automatic $HOME inside
    # this script.
    [switch]$NoCd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Same reason as wsl-deploy: wsl.exe emits UTF-16LE by default, which lands in
# PowerShell as strings full of NULs that no comparison will match. Without
# this the "is this distro installed" check below silently never matches.
$env:WSL_UTF8 = '1'

function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }

$distroName = "regulad-$Flavor"

# --- preflight -------------------------------------------------------------

wsl.exe --version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "WSL is not installed. Run .chezmoiscripts/00-nt/run_once_after_110-wsl-install.cmd, or 'wsl --install --no-distribution'."
}

if ((wsl.exe --list --quiet) -notcontains $distroName) {
    throw "'$distroName' is not installed. Deploy it first:  wsl-deploy $Flavor"
}

# --- work out where to land ------------------------------------------------

# wsl.exe --cd takes a Windows path directly and does the translation itself,
# so there is no wslpath round-trip to get wrong. It does need the path to be
# somewhere WSL can actually reach, though, and it fails the whole launch when
# it isn't -- leaving you with no shell at all rather than a shell in the
# wrong place. So the cases WSL cannot map are filtered out here and turned
# into a home-directory start with a note, which is the useful behaviour.
function Resolve-StartDirectory {
    if ($NoCd) { return $null }

    $current = $PWD

    # PowerShell's location can live on a provider with no filesystem path at
    # all -- HKLM:\, Cert:\, Env:\ -- where $PWD is meaningless to WSL.
    if ($current.Provider.Name -ne 'FileSystem') {
        Write-Note "current location is a $($current.Provider.Name) drive, starting at home instead"
        return $null
    }

    $path = $current.ProviderPath

    # UNC paths (\\server\share, and the \\wsl.localhost\... paths you get
    # from inside a distro) have no /mnt/<letter> equivalent.
    if ($path.StartsWith('\\')) {
        Write-Note "current directory is a UNC path, starting at home instead"
        return $null
    }

    # Only drives WSL automounts under /mnt are reachable. DrvFs covers local
    # disks; a mapped network drive is a drive letter WSL knows nothing about,
    # so it would fail the same way a UNC path does.
    $root = [System.IO.Path]::GetPathRoot($path)
    try {
        $driveType = [string]([System.IO.DriveInfo]::new($root)).DriveType
    } catch {
        Write-Note "could not identify the drive for $path, starting at home instead"
        return $null
    }
    if ($driveType -notin @('Fixed', 'Removable', 'Ram')) {
        Write-Note "$root is a $driveType drive, which WSL does not automount; starting at home instead"
        return $null
    }

    return $path
}

$startDir = Resolve-StartDirectory

# --- go --------------------------------------------------------------------

$wslArgs = @('-d', $distroName)
if ($null -ne $startDir) { $wslArgs += @('--cd', $startDir) }

# -Verbose to see where this decided to put you, without having to read the
# prompt of the shell it just opened.
Write-Verbose "wsl.exe $($wslArgs -join ' ')"

wsl.exe @wslArgs

# Pass the instance's exit status back out so `wsl-enter && ...` behaves. No
# throw-on-nonzero here on purpose: a shell exiting non-zero is ordinary, not
# a failure of this script.
exit $LASTEXITCODE
