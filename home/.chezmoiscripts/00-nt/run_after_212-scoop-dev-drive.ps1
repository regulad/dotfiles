# uv's and pnpm's data on the D: Dev Drive, beside the projects in
# D:\repositories, instead of in scoop's persist directory on C:. Hard links
# never cross volumes, so with these on C: every `uv sync` and `pnpm install`
# in a D: project copied files out of them instead of linking; on the Dev
# Drive they link, and the hundreds of thousands of small files get its
# faster scanning. The other caches have been there for a while
# (registry-system.reg, 060-dev-caches).
#
# Each folder moves to D:\packages\<app>\<name>, and its old place in
# scoop\persist becomes a directory junction to the new one. The tools are
# pointed at D: directly, so they do not go through the junction: uv by its
# per-user UV_* variables (and the user PATH entries for its shims), pnpm by
# storeDir/cacheDir/globalDir in its config.yaml. The junction stays for
# whatever recorded an old path: scoop's own links from apps\<app>\current
# into persist, venvs whose pyvenv.cfg names the old Python, shims that embed
# a tool's old location.
#
# pnpm's global bin directory moves too but is the one thing reached only
# through the junction, by scoop's PATH entry for apps\pnpm\current\bin. It
# has to be on D: with the store: go-ios's postinstall (570) renames its
# ios.exe from its package, in the store, into that directory, and a rename
# cannot cross volumes (EXDEV) -- through a junction to the same volume it
# can. Naming it directly would mean pnpm's globalBinDir, which pnpm refuses
# to run with unless that directory is already on the PATH of the process
# running it, the apply's own included.
#
# scoop puts both back on every update of the app: uv's manifest sets the UV_*
# variables to the persist paths (env_set), and pnpm's post_install runs
# `pnpm config set storeDir/cacheDir/stateDir` to them. So this runs on every
# apply, after 210-scoop-update, and points them at D: again; the junctions
# make the hours in between harmless. Before 501-503 and 570, which install uv
# tools and pnpm globals. (Those run with the environment chezmoi started
# with, so on the apply that moves things they still use the old paths,
# through the junctions; the next apply's shells have the new ones.)
#
# Moved, or started fresh. Nearly every file in these folders is a hard link
# (uv links its cache into tool environments, pnpm its store into everything
# it installs), and a copy to another volume turns each link into a file of
# its own: copying the caches would have roughly doubled them on D:, whose
# VHDX lives on C: anyway. So:
#   - uv's tools and Pythons move (robocopy; their links into the cache become
#     plain files, about 2 GiB). They hold what a reinstall would not bring
#     back: a tool installed by hand, a Python no script asked for. uv's
#     version aliases (cpython-3.12 -> cpython-3.12.13) are junctions; robocopy
#     /SJ copies them as junctions and they are re-aimed at D: afterwards.
#   - uv's cache and pnpm's store, cache and globals start empty on D:, and the
#     C: copies are deleted. The caches refill as they are used, and 570
#     installs the pnpm globals again later in the same apply, every one of
#     them being in .chezmoidata/pnpm-tools.toml. Moving pnpm's globals would
#     not even work: each install records its store's path and refuses to run
#     against a different one without a terminal to confirm in.
#   An existing pnpm project notices the new store at its next `pnpm install`
#   and offers to reinstall its node_modules.
#
# Nothing moves while uv or pnpm, or anything run from their folders, is
# running: a file in use can be neither moved nor deleted, and a half-moved
# tool environment is a broken one. A warning names what was running, and the
# next apply tries again. The one exception is this repo's own logon task
# that runs a uv tool for the whole session, chezmoi-pyghidra-mcp
# (503-pyghidra-mcp): waiting for it would mean waiting forever, so it is
# stopped for the move and started again at the end, by which time
# UV_TOOL_BIN_DIR, which its launcher reads, names D:. Each step is guarded on its result, so a finished
# move costs nothing: an existing junction to the right place, an unchanged
# variable or setting, is left alone.
#
# No elevation anywhere: everything is the user's own, and a junction needs no
# privilege.

$Persist = Join-Path $env:USERPROFILE 'scoop\persist'
$Apps = Join-Path $env:USERPROFILE 'scoop\apps'
$Root = 'D:\packages'

$Items = @(
    @{ App = 'uv'; Name = 'cache'; Mode = 'Fresh' }
    @{ App = 'uv'; Name = 'tools'; Mode = 'Move' }
    @{ App = 'uv'; Name = 'python'; Mode = 'Move' }
    @{ App = 'pnpm'; Name = 'store'; Mode = 'Fresh' }
    @{ App = 'pnpm'; Name = 'cache'; Mode = 'Fresh' }
    @{ App = 'pnpm'; Name = 'global'; Mode = 'Fresh' }
    @{ App = 'pnpm'; Name = 'bin'; Mode = 'Move' }
)

if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host "warning: $Root does not exist (050-dev-drive, 060-dev-caches); uv and pnpm keep their data in scoop\persist"
    exit 0
}

$Failed = 0

# Logon tasks of this repo's that keep a tool of the app running, and the
# process name that is left behind if stopping the task does not reach it
# (Stop-ScheduledTask ends the task's own process, not always its children).
$OwnTasks = @{
    uv = @(@{ Task = 'chezmoi-pyghidra-mcp'; Process = 'pyghidra-mcp' })
}
$Restart = [Collections.Generic.List[string]]::new()

function Stop-OwnTasks([string]$App) {
    foreach ($Own in @($OwnTasks[$App])) {
        if (-not $Own) { continue }
        $Task = Get-ScheduledTask -TaskName $Own.Task -ErrorAction SilentlyContinue
        if (-not $Task -or $Task.State -ne 'Running') { continue }
        Write-Host "notice: stopping $($Own.Task) while $App's data moves; it starts again afterwards"
        Stop-ScheduledTask -TaskName $Own.Task -ErrorAction SilentlyContinue
        $Restart.Add($Own.Task)
        $Deadline = (Get-Date).AddSeconds(15)
        do {
            $Left = @(Get-AppProcesses $App | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Own.Process, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
            if (-not $Left.Count) { break }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $Deadline)
        foreach ($Proc in $Left) { Stop-Process -Id $Proc.ProcessId -Force -ErrorAction SilentlyContinue }
    }
}

function Get-JunctionTarget([string]$Path) {
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($Item -and $Item.LinkType -eq 'Junction') { return @($Item.Target)[0] }
    return $null
}

function Test-SamePath([string]$A, [string]$B) {
    return $A.TrimEnd('\') -ieq $B.TrimEnd('\')
}

# Processes running anything of the app's: its own executable, or a command
# line naming its folders (a uv tool's Python, a node running a pnpm global).
function Get-AppProcesses([string]$App) {
    $Paths = @((Join-Path $Persist $App), (Join-Path $Apps $App)) | ForEach-Object { $_.TrimEnd('\') + '\' }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $Proc = $_
        @($Paths | Where-Object {
                ($Proc.ExecutablePath -and $Proc.ExecutablePath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase)) -or
                ($Proc.CommandLine -and $Proc.CommandLine.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0)
            }).Count -gt 0
    }
}

# ---------------------------------------------------------------------------
# 1. Move each folder and leave a junction behind.
# ---------------------------------------------------------------------------
$Done = @{}
foreach ($App in @($Items | ForEach-Object { $_.App } | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Apps "$App\current"))) {
        Write-Host "debug: scoop's $App is not installed; nothing of it to move"
        continue
    }
    $Busy = $null
    foreach ($Item in @($Items | Where-Object { $_.App -eq $App })) {
        $Old = Join-Path $Persist "$App\$($Item.Name)"
        $New = Join-Path $Root "$App\$($Item.Name)"
        $Key = "$App\$($Item.Name)"

        $Target = Get-JunctionTarget $Old
        if ($Target) {
            if (Test-SamePath $Target $New) {
                $Done[$Key] = $New
            }
            else {
                Write-Host "warning: $Old is a junction to $Target, not $New; leaving it"
            }
            continue
        }

        if (Test-Path -LiteralPath $Old) {
            if ($null -eq $Busy) {
                Stop-OwnTasks $App
                $Busy = @(Get-AppProcesses $App)
            }
            if ($Busy.Count) {
                $Names = ($Busy | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
                Write-Host "warning: not moving $App's $($Item.Name) to $New while $Names runs; the next apply tries again"
                continue
            }
            New-Item -ItemType Directory -Force -Path $New | Out-Null
            if ($Item.Mode -eq 'Move') {
                Write-Host "notice: moving $Old to $New"
                # /SJ /SL: junctions and symlinks as themselves, never their targets.
                & robocopy.exe $Old $New /E /MOVE /SJ /SL /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
                if ($LASTEXITCODE -ge 8) {
                    Write-Host "error: robocopy $Old -> $New failed (exit $LASTEXITCODE)"
                    $Failed++
                    continue
                }
                # The version aliases point into the old folder; aim them at the new one.
                foreach ($Link in @(Get-ChildItem -LiteralPath $New -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue | Where-Object { $_.LinkType -eq 'Junction' })) {
                    $LinkTarget = @($Link.Target)[0]
                    if ($LinkTarget -and $LinkTarget.StartsWith($Old.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                        $Retarget = $New.TrimEnd('\') + $LinkTarget.Substring($Old.TrimEnd('\').Length)
                        [IO.Directory]::Delete($Link.FullName)
                        New-Item -ItemType Junction -Path $Link.FullName -Target $Retarget | Out-Null
                    }
                }
            }
            else {
                Write-Host "notice: deleting $Old; $App starts its $($Item.Name) afresh in $New"
            }
            # rmdir /s deletes a junction or symlink inside without following it,
            # which Remove-Item -Recurse under Windows PowerShell cannot be
            # trusted to do. After a move it only finds empty folders left.
            & cmd.exe /d /c "rmdir /s /q `"$Old`"" 2>$null
            if (Test-Path -LiteralPath $Old) {
                Write-Host "error: could not empty $Old (a file in use?); the next apply tries again"
                $Failed++
                continue
            }
        }
        else {
            New-Item -ItemType Directory -Force -Path $New | Out-Null
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Old) | Out-Null
        }

        New-Item -ItemType Junction -Path $Old -Target $New | Out-Null
        if (Test-SamePath (Get-JunctionTarget $Old) $New) {
            Write-Host "notice: $Old is now a junction to $New"
            $Done[$Key] = $New
        }
        else {
            Write-Host "error: could not create the junction $Old -> $New"
            $Failed++
        }
    }
}

# ---------------------------------------------------------------------------
# 2. Point uv at D: directly: its per-user variables, and the user PATH entries
#    for its shims, wherever they name a moved folder by its persist path.
# ---------------------------------------------------------------------------
function ConvertTo-DevDrivePath([string]$Value) {
    foreach ($Key in $Done.Keys) {
        $OldPrefix = (Join-Path $Persist $Key).TrimEnd('\')
        if ((Test-SamePath $Value $OldPrefix) -or $Value.StartsWith($OldPrefix + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $Done[$Key] + $Value.Substring($OldPrefix.Length)
        }
    }
    return $Value
}

foreach ($Var in 'UV_CACHE_DIR', 'UV_TOOL_DIR', 'UV_TOOL_BIN_DIR', 'UV_PYTHON_INSTALL_DIR', 'UV_PYTHON_BIN_DIR') {
    $Value = [Environment]::GetEnvironmentVariable($Var, 'User')
    if (-not $Value) { continue }
    $Wanted = ConvertTo-DevDrivePath $Value
    if ($Wanted -ne $Value) {
        [Environment]::SetEnvironmentVariable($Var, $Wanted, 'User')
        Write-Host "notice: $Var = $Wanted (was $Value)"
    }
}

$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($UserPath) {
    $Entries = @($UserPath -split ';' | Where-Object { $_ -ne '' })
    $Rewritten = @($Entries | ForEach-Object { ConvertTo-DevDrivePath $_ })
    $Unique = [Collections.Generic.List[string]]::new()
    foreach ($Entry in $Rewritten) { if (-not ($Unique | Where-Object { Test-SamePath $_ $Entry })) { $Unique.Add($Entry) } }
    if (($Unique -join ';') -ne ($Entries -join ';')) {
        [Environment]::SetEnvironmentVariable('Path', ($Unique -join ';'), 'User')
        Write-Host 'notice: user PATH now names the uv shim folders on D:'
    }
}

# ---------------------------------------------------------------------------
# 3. Point pnpm at D: directly, through its own config. By the full path of
#    scoop's pnpm.exe, as scoop's post_install calls it, so no other pnpm on
#    PATH is asked.
# ---------------------------------------------------------------------------
$Pnpm = Join-Path $Apps 'pnpm\current\pnpm.exe'
if (Test-Path -LiteralPath $Pnpm) {
    foreach ($Setting in @(
            @{ Key = 'storeDir'; Item = 'pnpm\store' }
            @{ Key = 'cacheDir'; Item = 'pnpm\cache' }
            @{ Key = 'globalDir'; Item = 'pnpm\global' })) {
        if (-not $Done.ContainsKey($Setting.Item)) { continue }
        $Wanted = $Done[$Setting.Item]
        $Current = "$(& $Pnpm config get $Setting.Key 2>$null)".Trim()
        if (Test-SamePath $Current $Wanted) { continue }
        & $Pnpm config set $Setting.Key $Wanted
        $Now = "$(& $Pnpm config get $Setting.Key 2>$null)".Trim()
        if (Test-SamePath $Now $Wanted) {
            Write-Host "notice: pnpm $($Setting.Key) = $Wanted (was $Current)"
        }
        else {
            Write-Host "error: pnpm config set $($Setting.Key) did not take (reads back '$Now')"
            $Failed++
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Start again what step 1 stopped, now that the variables name D:.
# ---------------------------------------------------------------------------
foreach ($TaskName in $Restart) {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ((Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue).State -eq 'Running') {
        Write-Host "notice: started $TaskName again"
    }
    else {
        Write-Host "warning: $TaskName did not start again; it starts at the next logon"
    }
}

if ($Failed) {
    exit 1
}
