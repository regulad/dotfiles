# Takes packages this repo no longer installs off a machine that still has
# them. Dropping a package from 100-winget's or 200-scoop-install's list never
# uninstalls it, and 210-scoop-update's `scoop update --all` would go on
# upgrading a scoop leftover, so a package retired from either list gets an
# entry in $Retired below. Docker Desktop, whose removal takes more than an
# uninstall, has its own section after the table.
#
# run_onchange_: chezmoi re-runs this whenever its text changes, i.e. whenever
# an entry is added, and records it only after a clean exit. Every entry is
# guarded on its package being installed, so a re-run only does work for what
# is new, and anything that failed (exit 1 at the end) is tried again on the
# next apply. One failure does not stop the rest.
#
# 105: after 040-telnet-client and 100-winget, which install the replacements
# two entries wait for; ahead of 110/115 for Docker Desktop (see there) and of
# 210-scoop-update. On a fresh machine scoop is not there yet at 105, and
# neither is anything of scoop's to remove.
#
# An entry:
#   Manager  'winget' or 'scoop'. scoop uninstalls with --purge, taking the
#            package's persist directory with it.
#   Id       the winget package ID, or the scoop app name.
#   Why      what replaced it, for the notice.
#   Elevate  uninstall through sudo: a per-machine MSI, which a --silent
#            uninstall cannot elevate by itself. One UAC prompt each.
#   Close    processes to close first, whose files the uninstaller would
#            otherwise fail to remove.
#   Refuse   processes that block the uninstall instead: closing them would
#            lose work. The entry fails, so the next apply tries again.
#   Requires a file whose absence holds the uninstall back, so a machine is
#            never left without the replacement; RequiresWhy says what puts it
#            there.
#   Keep     paths the uninstaller leaves behind on purpose (user data); a
#            notice names the ones that exist.

$Retired = @(
    @{
        Manager = 'winget'
        Id      = 'Vencord.Vesktop'
        Why     = 'Discord with Vencord injected replaces it (600-vencord); Vesktop cannot receive rich presence'
        Close   = @('Vesktop')
        # Behind the %APPDATA%\vesktop link.
        Keep    = @(Join-Path $HOME '.config\vesktop')
    }
    @{
        Manager = 'winget'
        Id      = 'Oracle.VirtualBox'
        Why     = 'retired from 100-winget on 2026-11-13'
        Elevate = $true
        Refuse  = @('VirtualBoxVM', 'VBoxHeadless')
        # The manager window.
        Close   = @('VirtualBox')
        Keep    = @((Join-Path $HOME 'VirtualBox VMs'), (Join-Path $HOME '.VirtualBox'))
    }
    @{
        Manager = 'scoop'
        Id      = 'act'
        # It drives a Docker Engine API, and wslc keeps its dockerd inside its
        # own VM.
        Why     = 'nothing on Windows serves a Docker Engine API to run it against'
    }
    @{
        Manager = 'scoop'
        Id      = 'gradle'
        # 200-scoop-install says why: the manifest's post_install points a
        # per-user GRADLE_USER_HOME into scoop's persist directory, and scoop
        # cannot be told to skip a hook. That value stays (it has no uninstall
        # hook); registry-user.reg replaces it.
        Why     = 'projects bring their own Gradle through gradlew'
    }
    @{
        Manager     = 'scoop'
        Id          = 'telnet'
        # GNU inetutils 1.7 from 2009, on MinGW's abandoned MSYS1 runtime.
        Why         = "Windows' own Telnet Client replaces it"
        Requires    = Join-Path $env:SystemRoot 'System32\telnet.exe'
        RequiresWhy = '040-telnet-client enables it'
    }
    @{
        Manager     = 'scoop'
        Id          = 'npiperelay'
        # jstarks' original, frozen at 0.1.0 since 2020, lacks the -a the WSL
        # gpg-agent relay needs. A distro's relays find winget's copy once it
        # has applied the matching 008-wsl-agent-relays; until then a running
        # SSH relay there still points at scoop's and stops working.
        Why         = "winget's albertony.npiperelay replaces it"
        Requires    = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\npiperelay.exe'
        RequiresWhy = '100-winget installs albertony.npiperelay'
    }
)

$Failed = 0

function Wait-Until {
    param([scriptblock]$Condition, [int]$TimeoutSeconds = 60)
    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        if (& $Condition) { return $true }
        if ((Get-Date) -gt $Deadline) { return $false }
        Start-Sleep -Milliseconds 500
    }
}

# `scoop list <name>` is a substring query (`act` lists actionlint too), hence
# the anchored match on the name column; any version, since some are not
# numbers (telnet's is msys-inetutils-1.7-1). scoop is a .ps1 shim that sets no
# $LASTEXITCODE, so an uninstall is checked by listing again.
function Test-Installed {
    param([hashtable]$Entry)
    if ($Entry.Manager -eq 'scoop') {
        $Listing = & scoop list $Entry.Id 6>$null 2>$null | Out-String
        return ($Listing -match "(?m)^\s*$([regex]::Escape($Entry.Id))\s+\S")
    }
    & winget list --id $Entry.Id --exact --accept-source-agreements --disable-interactivity *> $null
    return ($LASTEXITCODE -eq 0)
}

$HasManager = @{
    winget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    scoop  = [bool](Get-Command scoop -ErrorAction SilentlyContinue)
}

foreach ($Entry in $Retired) {
    $Label = "$($Entry.Manager)'s $($Entry.Id)"
    if (-not $HasManager[$Entry.Manager]) {
        Write-Host "debug: $($Entry.Manager) is not installed, so neither is $Label"
        continue
    }
    if (-not (Test-Installed $Entry)) {
        Write-Host "debug: $Label is not installed"
        continue
    }
    if ($Entry.Requires -and -not (Test-Path -LiteralPath $Entry.Requires)) {
        Write-Host "error: not removing $Label while $($Entry.Requires) is missing; $($Entry.RequiresWhy)"
        $Failed++
        continue
    }
    $Blocking = @(if ($Entry.Refuse) { Get-Process -Name $Entry.Refuse -ErrorAction SilentlyContinue })
    if ($Blocking.Count) {
        $Names = ($Blocking | ForEach-Object { "$($_.Name) (PID $($_.Id))" }) -join ', '
        Write-Host "error: not removing $Label while $Names runs; close it and apply again"
        $Failed++
        continue
    }
    $Running = @(if ($Entry.Close) { Get-Process -Name $Entry.Close -ErrorAction SilentlyContinue })
    if ($Running.Count) {
        Write-Host "notice: closing $(($Running | ForEach-Object Name | Sort-Object -Unique) -join ', ') to uninstall $Label"
        $Running | Stop-Process -Force -ErrorAction SilentlyContinue
        $Running | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
    }

    Write-Host "notice: uninstalling $Label; $($Entry.Why)"
    if ($Entry.Manager -eq 'scoop') {
        & scoop uninstall $Entry.Id --purge
    }
    else {
        $Uninstall = @('uninstall', '--id', $Entry.Id, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity')
        if ($Entry.Elevate) { & sudo winget @Uninstall } else { & winget @Uninstall }
    }
    # Some uninstallers hand off to a copy of themselves in %TEMP% and return
    # at once, and winget with them (Vesktop's NSIS one does), so the result is
    # polled for.
    if (-not (Wait-Until { -not (Test-Installed $Entry) } -TimeoutSeconds 120)) {
        $Hint = if ($Entry.Elevate) { ' -- was the elevation prompt declined?' } else { '' }
        Write-Host "error: $Label is still installed$Hint"
        $Failed++
        continue
    }
    Write-Host "notice: $Label uninstalled"
    foreach ($Path in @($Entry.Keep)) {
        if ($Path -and (Test-Path -LiteralPath $Path)) {
            Write-Host "notice: $Path is left in place; delete it by hand if it is no longer wanted"
        }
    }
}

# ---------------------------------------------------------------------------
# Docker Desktop. Containers on Windows come from WSL's own wslc now, and
# 115-wsl-update holds WSL at the release that ships it -- a WSL reported to
# break Docker Desktop outright (microsoft/WSL#41759: the docker-desktop distro
# fails with "unknown filesystem type 'iso9660'"), which is why this runs ahead
# of 110/115. Destructive by design: Docker Desktop keeps its containers,
# images and volumes in its own WSL distro, and they go with it.
#
# 1. The application, plus the machine-wide directories Docker's uninstall
#    docs (docs.docker.com/desktop/uninstall) say it leaves behind. One sudo,
#    so one UAC prompt: the elevated shell waits for the uninstaller before it
#    deletes anything. Confirmed by polling for its effect. While it is still
#    installed (a declined prompt, say), 2 and 3 are skipped: they would take
#    the distros and data of a Docker Desktop that is still there.
$DockerLeft = $false
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop'
if (Test-Path -LiteralPath $UninstallKey) {
    $InstallDir = (Get-ItemProperty -LiteralPath $UninstallKey).InstallLocation
    if (-not $InstallDir) { $InstallDir = Join-Path $env:ProgramFiles 'Docker\Docker' }
    $Installer = Join-Path $InstallDir 'Docker Desktop Installer.exe'
    if (-not (Test-Path -LiteralPath $Installer)) {
        Write-Host "error: Docker Desktop is registered but $Installer is missing; remove it from Settings > Apps"
        $DockerLeft = $true
        $Failed++
    }
    else {
        Write-Host 'notice: uninstalling Docker Desktop; its containers, images and volumes go with it'
        $MachineDirs = @(
            (Join-Path $env:ProgramData 'Docker'),
            (Join-Path $env:ProgramData 'DockerDesktop'),
            (Join-Path $env:ProgramFiles 'Docker')
        )
        $Quoted = ($MachineDirs | ForEach-Object { "'$_'" }) -join ','
        & sudo powershell -NoProfile -NonInteractive -Command "Start-Process -FilePath '$Installer' -ArgumentList 'uninstall','--quiet' -Wait; Remove-Item -LiteralPath $Quoted -Recurse -Force -ErrorAction SilentlyContinue"

        if (-not (Wait-Until { -not (Test-Path -LiteralPath $UninstallKey) } -TimeoutSeconds 900)) {
            Write-Host 'error: Docker Desktop is still installed -- was the elevation prompt declined?'
            $DockerLeft = $true
            $Failed++
        }
        else {
            # The uninstaller drops its registry key before it has finished
            # deleting files (AppData\Roaming\Docker Desktop among them), so the
            # per-user cleanup below would race it. Wait for it to exit first.
            [void](Wait-Until { -not (Get-Process -Name 'Docker Desktop Installer' -ErrorAction SilentlyContinue) } -TimeoutSeconds 300)
            Write-Host 'notice: Docker Desktop uninstalled'
        }
    }
}
else {
    Write-Host 'debug: Docker Desktop is not installed'
}

# 2. Its WSL distros. The uninstaller normally unregisters them; this catches
#    the ones it leaves (docker-desktop-data is the pre-4.30 layout). wsl.exe
#    writes UTF-16 unless WSL_UTF8 is exactly 1, which garbles the names for
#    -contains under both PowerShell hosts.
$env:WSL_UTF8 = '1'
if ($DockerLeft) {
    Write-Host 'warning: leaving the docker-desktop WSL distros and per-user data alone while Docker Desktop is installed'
}
elseif (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $Distros = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim() })
    foreach ($Distro in @('docker-desktop', 'docker-desktop-data')) {
        if ($Distros -contains $Distro) {
            Write-Host "notice: unregistering the $Distro WSL distro"
            & wsl.exe --unregister $Distro
            if ($LASTEXITCODE -ne 0) {
                Write-Host "error: wsl --unregister $Distro failed"
                $Failed++
            }
        }
    }
}

# 3. Per-user leftovers, from the same Docker doc. ~/.docker goes too: nothing
#    on Windows runs a docker CLI any more, and the copy Docker Desktop wrote
#    points credsStore at its own docker-credential-desktop.
foreach ($Dir in @(if (-not $DockerLeft) {
            (Join-Path $env:LOCALAPPDATA 'Docker')
            (Join-Path $env:APPDATA 'Docker')
            (Join-Path $env:APPDATA 'Docker Desktop')
            (Join-Path $HOME '.docker')
        })) {
    if (Test-Path -LiteralPath $Dir) {
        Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $Dir) {
            Write-Host "warning: could not fully remove $Dir; delete it by hand"
        }
        else {
            Write-Host "notice: removed $Dir"
        }
    }
}

if ($Failed) {
    exit 1
}
