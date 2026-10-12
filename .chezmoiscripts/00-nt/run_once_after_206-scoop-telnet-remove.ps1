# Takes scoop's telnet off a machine that still has it. 200-scoop-install
# dropped it from its list for Windows' own Telnet Client, which
# 040-telnet-client enables; dropping a package from a list never uninstalls
# it, and 210-scoop-update would keep upgrading the leftover. scoop's telnet
# was GNU inetutils 1.7 from 2009 on MinGW's abandoned MSYS1 runtime.
#
# Only once the inbox client is there, so a machine is never left without a
# telnet: 040 runs first, and if it could not enable the feature (a declined
# elevation prompt, say) this fails too and the next apply tries again.
#
# run_once_: chezmoi records the script only after a clean exit. Same shape as
# 205-scoop-gradle-remove, except that the row match takes any version: this
# one is msys-inetutils-1.7-1, not a number.
function Test-ScoopTelnet {
    $Listing = & scoop list telnet 6>$null 2>$null | Out-String
    return ($Listing -match '(?m)^\s*telnet\s+\S')
}

$InboxTelnet = Join-Path $env:SystemRoot 'System32\telnet.exe'

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host 'debug: scoop is not installed, so neither is its telnet'
}
elseif (-not (Test-ScoopTelnet)) {
    Write-Host "debug: scoop's telnet is not installed"
}
elseif (-not (Test-Path -LiteralPath $InboxTelnet)) {
    Write-Host "error: not removing scoop's telnet while $InboxTelnet is missing; 040-telnet-client enables it"
    exit 1
}
else {
    Write-Host "notice: uninstalling scoop's telnet; Windows' own Telnet Client replaces it, see 040-telnet-client"
    & scoop uninstall telnet --purge
    if (Test-ScoopTelnet) {
        Write-Host 'error: scoop uninstall telnet did not remove it'
        exit 1
    }
}
