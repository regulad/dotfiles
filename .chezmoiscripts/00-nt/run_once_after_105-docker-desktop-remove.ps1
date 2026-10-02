# Takes Docker Desktop off a machine that still has it. 100-winget no longer
# installs it: containers on Windows come from WSL's own wslc now, and
# 115-wsl-update holds WSL at the release that ships it. Dropping a package
# from a list never uninstalls it, though, and the WSL that 115 enforces is
# reported to break Docker Desktop outright (microsoft/WSL#41759: the
# docker-desktop distro fails with "unknown filesystem type 'iso9660'"), so
# this runs ahead of 110/115.
#
# Destructive by design: Docker Desktop keeps its containers, images and
# volumes in its own WSL distro, and they go with it.
#
# run_once_: chezmoi records the script only after a clean exit, so a declined
# UAC prompt (exit 1 below) means the next apply tries again. Every step is
# guarded on the thing it removes, so a re-run finds nothing to do.
#
# Same elevation shape as 170-firefox-policies.ps1 and 035-sshd-user-session:
# stay unelevated, hand the one privileged step to sudo, and confirm it by
# polling for its effect -- sudo is pinned to Force New Window mode here (see
# 030-w32time.cmd), which returns early and drops the child's exit code.

function Wait-Until {
    param([scriptblock]$Condition, [int]$TimeoutSeconds = 60)
    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        if (& $Condition) { return $true }
        if ((Get-Date) -gt $Deadline) { return $false }
        Start-Sleep -Milliseconds 500
    }
}

# ---------------------------------------------------------------------------
# 1. The application, plus the machine-wide directories Docker's uninstall
#    docs (docs.docker.com/desktop/uninstall) say it leaves behind. One sudo,
#    so one UAC prompt: the elevated shell waits for the uninstaller before it
#    deletes anything.
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop'
if (Test-Path -LiteralPath $UninstallKey) {
    $InstallDir = (Get-ItemProperty -LiteralPath $UninstallKey).InstallLocation
    if (-not $InstallDir) { $InstallDir = Join-Path $env:ProgramFiles 'Docker\Docker' }
    $Installer = Join-Path $InstallDir 'Docker Desktop Installer.exe'
    if (-not (Test-Path -LiteralPath $Installer)) {
        Write-Host "error: Docker Desktop is registered but $Installer is missing; remove it from Settings > Apps"
        exit 1
    }

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
        exit 1
    }
    # The uninstaller drops its registry key before it has finished deleting
    # files (AppData\Roaming\Docker Desktop among them), so the per-user
    # cleanup below would race it. Wait for it to exit first.
    [void](Wait-Until { -not (Get-Process -Name 'Docker Desktop Installer' -ErrorAction SilentlyContinue) } -TimeoutSeconds 300)
    Write-Host 'notice: Docker Desktop uninstalled'
}
else {
    Write-Host 'debug: Docker Desktop is not installed'
}

# ---------------------------------------------------------------------------
# 2. Its WSL distros. The uninstaller normally unregisters them; this catches
#    the ones it leaves (docker-desktop-data is the pre-4.30 layout). wsl.exe
#    writes UTF-16 unless WSL_UTF8 is exactly 1, which garbles the names for
#    -contains under both PowerShell hosts.
$env:WSL_UTF8 = '1'
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $Distros = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim() })
    foreach ($Distro in @('docker-desktop', 'docker-desktop-data')) {
        if ($Distros -contains $Distro) {
            Write-Host "notice: unregistering the $Distro WSL distro"
            & wsl.exe --unregister $Distro
            if ($LASTEXITCODE -ne 0) {
                Write-Host "error: wsl --unregister $Distro failed"
                exit 1
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 3. Per-user leftovers, from the same Docker doc. ~/.docker goes too: nothing
#    on Windows runs a docker CLI any more, and the copy Docker Desktop wrote
#    points credsStore at its own docker-credential-desktop.
foreach ($Dir in @(
        (Join-Path $env:LOCALAPPDATA 'Docker'),
        (Join-Path $env:APPDATA 'Docker'),
        (Join-Path $env:APPDATA 'Docker Desktop'),
        (Join-Path $HOME '.docker'))) {
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

# ---------------------------------------------------------------------------
# 4. act. It drives a Docker Engine API, and nothing on Windows serves one now
#    (wslc keeps its dockerd inside its own VM), so 200-scoop-install dropped
#    it. Same leftover problem as above: a list removal is not an uninstall.
#    `scoop list act` is a substring query (it lists actionlint too), hence the
#    anchored match on the name column. scoop is a .ps1 shim that sets no
#    $LASTEXITCODE, so the uninstall is checked by listing again.
function Test-ScoopAct {
    $Listing = & scoop list act 6>$null 2>$null | Out-String
    return ($Listing -match '(?m)^\s*act\s+\d')
}
if ((Get-Command scoop -ErrorAction SilentlyContinue) -and (Test-ScoopAct)) {
    Write-Host 'notice: uninstalling act (no Docker Engine API on Windows to run it against)'
    & scoop uninstall act
    if (Test-ScoopAct) {
        Write-Host 'error: scoop uninstall act did not remove it'
        exit 1
    }
}
