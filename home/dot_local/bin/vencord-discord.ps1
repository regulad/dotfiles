# vencord-discord: puts the Vencord build in ~/repositories/Vencord into
# Discord stable, and restarts Discord. The Windows counterpart of
# ~/.local/bin/vencord-discord on macOS and Linux; the doskey macro of the
# same name runs it from cmd.
#
#   vencord-discord inject       inject unless Discord already loads this build
#                                (600-vencord runs this after every build)
#   vencord-discord restart      close Discord and start it again
#   vencord-discord dev [args]   pnpm i, pnpm build [args], inject, restart:
#                                one round of plugin work, for a person or an
#                                agent. Renderer-only changes would also load
#                                with Ctrl+R; a plugin's native.ts, the patcher
#                                and the preload need the restart.
#
# `pnpm inject` runs Vencord's installer against this build
# (VENCORD_DEV_INSTALL): in Discord's newest app-* it renames
# resources\app.asar to _app.asar and writes a stub app.asar that requires the
# build's dist\patcher.js. Vencord moves that stub to each newer app-* itself
# as Discord updates (src/main/persistAfterDiscordUpdates.ts), so inject only
# acts on a new install, or on a stub that points at some other Vencord.
#
# Windows PowerShell 5.1 and pwsh alike. No $ErrorActionPreference = 'Stop':
# exit codes are checked explicitly, as in the hookscripts. $args rather than
# a param() block, which would refuse build arguments such as --dev as
# parameters it does not have.
$Command = if ($args.Count) { [string]$args[0] } else { '' }
$BuildArgs = @($args | Select-Object -Skip 1)

$VencordDir = Join-Path $HOME 'repositories\Vencord'
$DiscordDir = Join-Path $env:LOCALAPPDATA 'Discord'

function Get-DiscordResources {
    $App = Get-ChildItem -LiteralPath $DiscordDir -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Where-Object Name -match '^app-\d+(\.\d+)+$' |
        Sort-Object { [version]$_.Name.Substring(4) } | Select-Object -Last 1
    if ($App) { Join-Path $App.FullName 'resources' }
}

# The stub names the patcher as a JSON string, hence the doubled backslashes.
function Test-Injected([string]$Resources) {
    $Stub = Join-Path $Resources 'app.asar'
    (Test-Path -LiteralPath (Join-Path $Resources '_app.asar')) -and
    (Test-Path -LiteralPath $Stub -PathType Leaf) -and
    [IO.File]::ReadAllText($Stub).Contains('repositories\\Vencord\\dist\\patcher.js')
}

# All of Discord's processes, not just one: app.asar cannot be renamed while
# any of them has it open. Returns whether Discord was running.
function Stop-Discord {
    $Running = @(Get-Process -Name Discord -ErrorAction SilentlyContinue)
    if ($Running.Count) {
        $Running | Stop-Process -Force -ErrorAction SilentlyContinue
        $Running | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
    }
    return [bool]$Running.Count
}

function Start-Discord {
    Start-Process -FilePath (Join-Path $DiscordDir 'Update.exe') -ArgumentList '--processStart', 'Discord.exe'
}

# Injects unless Discord already loads this build. Leaves Discord's running
# state to the caller. Returns 0 when injected, 1 when it could not be, 2 when
# there is no Discord to inject into.
function Invoke-Inject {
    $Resources = Get-DiscordResources
    if (-not $Resources) {
        Write-Host "notice: Discord is not installed in $DiscordDir; not injecting Vencord"
        return 2
    }
    $Version = Split-Path -Leaf (Split-Path -Parent $Resources)
    if (Test-Injected $Resources) {
        Write-Host "debug: Vencord is already injected into Discord $Version"
        return 0
    }
    if (-not (Test-Path -LiteralPath (Join-Path $VencordDir 'dist\patcher.js'))) {
        Write-Host "error: $VencordDir has no build to inject; 600-vencord builds it"
        return 1
    }
    # runInstaller.mjs exits 0 even when the installer fails, so the result
    # is checked rather than the exit code. Out-Host keeps its output out of
    # this function's return value.
    & pnpm -C $VencordDir inject --branch stable | Out-Host
    if (Test-Injected $Resources) {
        Write-Host "notice: injected Vencord into Discord $Version"
        return 0
    }
    Write-Host "error: could not inject Vencord into Discord $Version; see the installer's output above"
    return 1
}

switch ($Command) {
    'inject' {
        $Resources = Get-DiscordResources
        $WasRunning = $false
        if ($Resources -and -not (Test-Injected $Resources) -and (Get-Process -Name Discord -ErrorAction SilentlyContinue)) {
            Write-Host 'notice: closing Discord to inject Vencord; it is started again afterwards'
            $WasRunning = Stop-Discord
        }
        $Status = Invoke-Inject
        if ($WasRunning) { Start-Discord }
        exit $(if ($Status -eq 1) { 1 } else { 0 })
    }
    'restart' {
        [void](Stop-Discord)
        Start-Discord
    }
    'dev' {
        & pnpm -C $VencordDir i --config.confirmModulesPurge=false
        if ($LASTEXITCODE -ne 0) {
            Write-Host "error: pnpm i failed in $VencordDir"
            exit 1
        }
        & pnpm -C $VencordDir build @BuildArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "error: pnpm build failed in $VencordDir"
            exit 1
        }
        [void](Stop-Discord)
        $Status = Invoke-Inject
        if ($Status -eq 2) {
            Write-Host 'error: no Discord to load the build into'
            exit 1
        }
        Start-Discord
        if ($Status -ne 0) { exit 1 }
        Write-Host 'notice: Discord restarted on the new build'
    }
    default {
        Write-Host 'usage: vencord-discord inject | restart | dev [pnpm build arguments]'
        exit 2
    }
}
