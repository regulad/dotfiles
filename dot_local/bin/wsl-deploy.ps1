<#
.SYNOPSIS
    Deploy the newest regulad/dotfiles WSL image and drop into its OOBE.

.DESCRIPTION
    Finds the most recent non-expired wsl-<flavor>-<arch> build artifact,
    downloads it to ~/Downloads, replaces any existing regulad-<flavor>
    instance, and imports it. The first interactive shell runs /etc/oobe.sh, which pulls the
    Bitwarden API credentials off this machine's own .secrets/.bwrc and runs
    the privileged chezmoi apply.

    The tarballs live as GitHub Actions artifacts rather than release assets
    because they are ~5 GB and a release asset is capped at 2 GB. Artifacts
    expire (currently 14 days), so this deliberately skips expired ones rather
    than failing on a dead download link.

    Every image carries the commit it was built from in /etc/dotfiles-commit
    (written by .github/workflows/wsl-package.yml). When the instance is
    already installed, this reads that back and says whether it is the newest
    build or is behind one -- nothing in WSL itself tracks that.

    After importing, offers to make the new instance the default distribution.

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
    wsl-deploy.ps1 -SetDefault # and make it what a bare `wsl` starts
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

    # Keep the downloaded .wsl in ~/Downloads. Off by default: import copies everything into
    # the instance's VHD, so the tarball is ~5 GB of dead weight afterwards.
    [switch]$KeepDownload,

    # Make the new instance the default distribution without asking. Without
    # this you get a y/N prompt after the import; -Force suppresses that prompt
    # and leaves the default alone, since -Force means "don't ask me about
    # destroying the old instance", not "make every choice for me".
    [switch]$SetDefault
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
$newestCommit = $artifact.workflow_run.head_sha
Write-Note "run $($artifact.workflow_run.id), commit $($newestCommit.Substring(0, 7)), built $($artifact.created_at), $sizeGb GB"

# --- compare against what is already installed -----------------------------

# Nothing about a WSL instance records where it came from -- `wsl --list` knows
# a name and a VHD path and nothing else -- so the image carries it instead:
# the overlay step of .github/workflows/wsl-package.yml writes the commit the
# image was built from to /etc/dotfiles-commit, and the artifact's workflow run
# names the commit it built, so the two compare directly.
#
# Read with --exec as root: no login shell, so none of the dotfiles run, and no
# OOBE, which WSL starts only for an interactive shell. This does start the
# instance if it is stopped. Anything other than one 40-hex line -- the file is
# missing (an image from before it existed), the instance will not start --
# counts as unknown rather than failing the deploy.
function Get-InstalledCommit {
    try {
        $out = wsl.exe -d $distroName -u root --exec cat /etc/dotfiles-commit 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $sha = "$($out | Select-Object -First 1)".Trim()
        if ($sha -match '^[0-9a-f]{40}$') { return $sha }
    } catch { }
    return $null
}

$installedAlready = (wsl.exe --list --quiet) -contains $distroName

if ($installedAlready) {
    $installedCommit = Get-InstalledCommit
    if ($null -eq $installedCommit) {
        Write-Note "installed instance has no readable /etc/dotfiles-commit, so its build is unknown"
        Write-Note "(built before images carried it, or imported by hand)"
    } elseif ($installedCommit -eq $newestCommit) {
        Write-Host ""
        Write-Host "  '$distroName' is already running this exact build (commit $($installedCommit.Substring(0, 7)))." -ForegroundColor Green
        Write-Host "  Redeploying downloads $sizeGb GB again and resets the instance." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "  a newer build is available." -ForegroundColor Cyan
        Write-Host "    installed: commit $($installedCommit.Substring(0, 7))" -ForegroundColor Cyan
        Write-Host "    newest:    commit $($newestCommit.Substring(0, 7)), run $($artifact.workflow_run.id), built $($artifact.created_at)" -ForegroundColor Cyan
        Write-Host ""
    }
}

# --- check there is room ---------------------------------------------------

# The tarball is downloaded and then expanded into a VHD, so both exist at
# once. Roughly 4x the compressed size covers the download, the zip gh wraps
# it in, and the expanded filesystem.
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
$needGb = [math]::Round($sizeGb * 4, 2)
if ($freeGb -lt $needGb) {
    throw "need roughly $needGb GB free on C: for the download and import, but only $freeGb GB is available"
}

# --- confirm replacing any existing instance -------------------------------

# Asked before the download, so saying no costs nothing, but carried out only
# after it: unregistering first meant a failed or interrupted download left no
# instance at all.
if ($installedAlready) {
    Write-Host ""
    Write-Host "  '$distroName' is already installed." -ForegroundColor Yellow
    Write-Host "  Replacing it UNREGISTERS it: its disk, and anything in it that" -ForegroundColor Yellow
    Write-Host "  is not pushed somewhere, is destroyed. There is no undo." -ForegroundColor Yellow
    Write-Host "  (It stays untouched until the new image has fully downloaded.)" -ForegroundColor Yellow
    Write-Host ""

    if (-not $Force) {
        $reply = Read-Host "  Replace '$distroName'? [y/N]"
        # Compared as "$reply", never bare. With no console to read -- stdin
        # redirected or at EOF -- Read-Host outputs nothing at all, and
        # `-notmatch` on that yields an empty array, which `if` reads as false:
        # the bare form skipped this return and went on to replace the
        # instance. The string is empty instead, and so a no.
        if ("$reply" -notmatch '^[Yy]') {
            Write-Step 'left the existing instance alone; nothing was changed.'
            return
        }
    }
}

# --- download --------------------------------------------------------------

# Into ~/Downloads, under the name .github/workflows/wsl-package.yml packs it
# as. Looked for by that exact name rather than any *.wsl, since Downloads holds
# other things and a stray .wsl there must never be what gets imported. A copy
# left by an earlier -KeepDownload run goes first, for the same reason.
$downloadDir = Join-Path $HOME 'Downloads'
$tarballPath = Join-Path $downloadDir "regulad-$Flavor-$arch.wsl"
if (Test-Path -LiteralPath $tarballPath) { Remove-Item -LiteralPath $tarballPath -Force }

# `gh run download` prints nothing at all for the whole transfer -- no bar, no
# byte count, no timeout -- so a 5 GB fetch looks identical to a hang for ten
# minutes. This wraps it in a progress readout.
#
# The bytes are measured from the process rather than from a file on purpose.
# gh buffers the archive into %TEMP%\gh-artifact.<n>.zip and only unpacks into
# --dir at the very end, so the destination sits empty for the entire download;
# and the zip's own directory entry does not keep up -- measured at 0 bytes
# while the process had demonstrably written 129 MB. WriteTransferCount is the
# number that actually tracks.
#
# It counts the unpack as well as the download, which is why this reports two
# phases against 2x the artifact size rather than pretending the download is
# the whole job.
function Invoke-GhDownloadWithProgress {
    param(
        [string[]]$GhArgs,
        [long]$ExpectedBytes
    )

    $proc = Start-Process gh -ArgumentList $GhArgs -PassThru -NoNewWindow
    $started = Get-Date
    $lastBytes = 0L
    $lastTime = $started
    $rate = 0.0
    # A redirected console makes carriage-return updates unreadable, so fall
    # back to occasional whole lines when this is not a terminal.
    $interactive = -not [Console]::IsOutputRedirected
    $nextMilestone = 0.05
    # Declared up front: Set-StrictMode -Version Latest makes reading an
    # unassigned variable a terminating error, and the phase comparison below
    # reads this on the very first iteration.
    $lastPhase = ''

    function Get-WrittenBytes {
        param([int]$RootPid)
        # Sum the launched process and its children: gh forks a worker, and it
        # is the worker that does the writing (the parent stayed at 0 bytes).
        $all = @(Get-CimInstance Win32_Process -Filter "Name='gh.exe'" -ErrorAction SilentlyContinue)
        $mine = $all | Where-Object { $_.ProcessId -eq $RootPid -or $_.ParentProcessId -eq $RootPid }
        if (-not $mine) { return 0L }
        return ([long]($mine | Measure-Object -Property WriteTransferCount -Sum).Sum)
    }

    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 1000
        $written = Get-WrittenBytes -RootPid $proc.Id
        $now = Get-Date

        $span = ($now - $lastTime).TotalSeconds
        if ($span -gt 0 -and $written -ge $lastBytes) {
            $instant = ($written - $lastBytes) / $span
            # Smoothed, so the readout does not flap between samples.
            $rate = if ($rate -eq 0) { $instant } else { ($rate * 0.7) + ($instant * 0.3) }
        }
        $lastBytes = $written
        $lastTime = $now

        if ($written -le $ExpectedBytes) {
            $phase = 'downloading'
            $done = $written
            $total = $ExpectedBytes
        } else {
            $phase = 'extracting '
            $done = $written - $ExpectedBytes
            $total = $ExpectedBytes
        }
        # The unpacked .wsl is not byte-for-byte the size of the zip that held
        # it, so the extract phase can run slightly past its own estimate.
        # Clamp for display rather than showing "5.63 / 5.41 GB".
        if ($done -gt $total) { $done = $total }
        $pct = if ($total -gt 0) { [math]::Min(100, [math]::Round(100 * $done / $total)) } else { 0 }

        # Each phase gets its own milestone sequence. Without the reset the
        # counter would still be sitting at 100% from the download when the
        # extract starts over near zero, and a redirected console would print
        # nothing at all for the whole second phase.
        if ($phase -ne $lastPhase) {
            $nextMilestone = 0.05
            $lastPhase = $phase
        }

        $eta = ''
        if ($rate -gt 0) {
            $remaining = (2 * $ExpectedBytes) - $written
            if ($remaining -gt 0) {
                $secs = [int]($remaining / $rate)
                $eta = '  eta {0:mm\:ss}' -f [timespan]::FromSeconds($secs)
            }
        }

        $line = '    {0} {1,3}%  {2,6:N2} / {3,6:N2} GB  {4,5:N1} MB/s{5}' -f `
            $phase, $pct, ($done / 1GB), ($total / 1GB), ($rate / 1MB), $eta

        if ($interactive) {
            Write-Host ("`r" + $line.PadRight(70)) -NoNewline -ForegroundColor DarkGray
        } elseif ($total -gt 0 -and ($done / $total) -ge $nextMilestone) {
            Write-Host $line -ForegroundColor DarkGray
            $nextMilestone = [math]::Floor(($done / $total) / 0.05) * 0.05 + 0.05
        }
    }

    $proc.WaitForExit()
    if ($interactive) { Write-Host "`r".PadRight(72) -NoNewline; Write-Host "`r" -NoNewline }

    $elapsed = (Get-Date) - $started
    Write-Note ('transfer finished in {0:mm\:ss}' -f $elapsed)

    if ($proc.ExitCode -ne 0) {
        throw "gh run download failed with exit code $($proc.ExitCode)"
    }
}

try {
    Write-Step "downloading $sizeGb GB to $downloadDir (this takes a while)"
    Invoke-GhDownloadWithProgress `
        -GhArgs @('run', 'download', "$($artifact.workflow_run.id)", '--repo', $Repo, '--name', $artifactName, '--dir', $downloadDir) `
        -ExpectedBytes ([long]$artifact.size_in_bytes)

    if (-not (Test-Path -LiteralPath $tarballPath -PathType Leaf)) {
        throw "artifact $artifactName did not contain $(Split-Path -Leaf $tarballPath)"
    }

    # --- replace any existing instance -------------------------------------

    # Only now, with the new image on disk. wsl.exe is asked again rather than
    # trusting the lookup from before the download, which takes long enough for
    # the instance to have been removed by hand in the meantime; and only an
    # instance the user was asked about above is ever unregistered.
    if ($installedAlready -and ((wsl.exe --list --quiet) -contains $distroName)) {
        Write-Step "unregistering $distroName"
        wsl.exe --unregister $distroName
        Assert-NativeSuccess "wsl --unregister $distroName"
    }

    # --- import ------------------------------------------------------------

    Write-Step "importing as '$distroName' at $installPath"
    $installArgs = @(
        '--install'
        '--from-file', $tarballPath
        '--name', $distroName
        '--location', $installPath
        '--no-launch'
    )
    # Finish installing before opening an interactive shell: the launch, and
    # with it OOBE, comes at the very end, after the default-distribution
    # prompt below. The instance carries its own provenance in
    # /etc/dotfiles-commit, so there is nothing to record here.

    wsl.exe @installArgs
    Assert-NativeSuccess 'wsl --install --from-file'
}
finally {
    if (-not $KeepDownload -and (Test-Path -LiteralPath $tarballPath)) {
        Write-Note "removing $tarballPath"
        Remove-Item -LiteralPath $tarballPath -Force -ErrorAction SilentlyContinue
    }
}

# --- default distribution --------------------------------------------------

# `wsl` with no -d starts the default, and on this machine that is whatever was
# installed first -- historically docker-desktop, which is not a thing anyone
# wants a shell in. Offered rather than assumed: changing the default silently
# would surprise anything that relies on it.
function Get-DefaultDistro {
    # `wsl --list --verbose` marks the default with a leading asterisk, which is
    # the documented way to identify it. The ordering of `--list --quiet` is not
    # specified anywhere, so "the first one" is not safe to rely on even though
    # it happens to be the default today.
    foreach ($line in (wsl.exe --list --verbose)) {
        if ($line -match '^\s*\*\s+(\S+)') { return $Matches[1] }
    }
    return $null
}

$currentDefault = Get-DefaultDistro
if ($currentDefault -eq $distroName) {
    Write-Note "'$distroName' is already the default distribution"
} else {
    $makeDefault = $false
    if ($SetDefault) {
        $makeDefault = $true
    } elseif (-not $Force) {
        Write-Host ""
        if ($currentDefault) {
            Write-Host "  the default WSL distribution is currently '$currentDefault'." -ForegroundColor Yellow
        } else {
            Write-Host "  there is no default WSL distribution set." -ForegroundColor Yellow
        }
        Write-Host "  The default is what a bare 'wsl' starts." -ForegroundColor Yellow
        $reply = Read-Host "  Make '$distroName' the default? [y/N]"
        # "$reply" for the same reason as the replace prompt above.
        $makeDefault = "$reply" -match '^[Yy]'
    }

    if ($makeDefault) {
        wsl.exe --set-default $distroName
        Assert-NativeSuccess "wsl --set-default $distroName"
        Write-Step "'$distroName' is now the default distribution"
    } elseif ($currentDefault) {
        Write-Note "left '$currentDefault' as the default; change it with: wsl --set-default $distroName"
    } else {
        Write-Note "no default set; make this one the default with: wsl --set-default $distroName"
    }
}

# --- what happens next -----------------------------------------------------

if (-not $NoLaunch) {
    Write-Step "starting '$distroName'"
    # Launch without a command so WSL runs the image's first-run OOBE.
    wsl.exe -d $distroName
    Assert-NativeSuccess "wsl -d $distroName"
}

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
