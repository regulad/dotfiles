# Takes scoop's npiperelay off a machine that still has it. 200-scoop-install
# dropped it from its list for albertony's fork, which 100-winget installs:
# scoop's is jstarks' original, frozen at 0.1.0 since 2020, and lacks the -a
# the WSL gpg-agent relay needs. Dropping a package from a list never
# uninstalls it, and 210-scoop-update would keep upgrading the leftover.
#
# Only once winget's is there, so the WSL relays are never left without an
# npiperelay: 100 runs first, and if it could not install the fork this fails
# too and the next apply tries again. The WSL relays find winget's copy, not
# scoop's, once the distro has applied the matching 008-wsl-agent-relays;
# until then a running SSH relay still points at scoop's and stops working
# when this removes it.
#
# run_once_: chezmoi records the script only after a clean exit. Same shape as
# 206-scoop-telnet-remove.
function Test-ScoopNpiperelay {
    $Listing = & scoop list npiperelay 6>$null 2>$null | Out-String
    return ($Listing -match '(?m)^\s*npiperelay\s+\S')
}

$WingetNpiperelay = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\npiperelay.exe'

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host 'debug: scoop is not installed, so neither is its npiperelay'
}
elseif (-not (Test-ScoopNpiperelay)) {
    Write-Host "debug: scoop's npiperelay is not installed"
}
elseif (-not (Test-Path -LiteralPath $WingetNpiperelay)) {
    Write-Host "error: not removing scoop's npiperelay while $WingetNpiperelay is missing; 100-winget installs albertony.npiperelay"
    exit 1
}
else {
    Write-Host "notice: uninstalling scoop's npiperelay; winget's albertony.npiperelay replaces it, see 100-winget"
    & scoop uninstall npiperelay --purge
    if (Test-ScoopNpiperelay) {
        Write-Host 'error: scoop uninstall npiperelay did not remove it'
        exit 1
    }
}
