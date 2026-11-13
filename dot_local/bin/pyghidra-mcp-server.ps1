# THIS FILE IS MANAGED BY CHEZMOI!
#
# Launcher for Claude Code's own headless Ghidra: pyghidra-mcp serving MCP over
# streamable HTTP on loopback, with no Ghidra window anywhere. This is what the
# `chezmoi-pyghidra-mcp` logon task executes -- registered by
# .chezmoiscripts/00-nt/503-pyghidra-mcp.ps1, which also passes the port -- and
# the `ghidra` entry in ~/.claude.json points Claude at it. It is also runnable
# by hand, which is the easiest way to watch it start:
#
#     .local\bin\pyghidra-mcp-server.ps1 -Port 18489
#
# One long-lived server rather than a stdio server per Claude session: Ghidra
# locks a project to one process (a second pyghidra-mcp on the same project
# dies in DefaultProjectData.initLock), and one process keeps analysing a large
# binary in the background between sessions.
#
# A hard kill -- logoff, shutdown, a re-registration -- costs only an import
# still in flight. The next start reopens the project over the stale lock file
# with every finished analysis and search index intact (tested 2026-11-12).

param(
    [Parameter(Mandatory = $true)]
    [int]$Port
)

$ErrorActionPreference = 'Stop'

# The project (claude.gpr, claude.rep) and pyghidra-mcp's own artifacts beside
# it (claude-pyghidra-mcp: downloaded PDBs, Chroma search index, GZF cache).
# Not under ~/.local/share: Ghidra refuses a project path with any element
# starting with '.' ("Path element starting with '.' is not permitted", from
# ProjectLocator), so it lives in the Windows-native per-user location. The
# logs have no such restriction and sit with LanguageTool's.
$DataDir = Join-Path $env:LOCALAPPDATA 'pyghidra-mcp'
$LogDir = Join-Path $HOME '.local\state\pyghidra-mcp'
$ScoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }

New-Item -ItemType Directory -Force -Path $DataDir, $LogDir | Out-Null
$LauncherLog = Join-Path $LogDir 'launcher.log'
$StdoutLog = Join-Path $LogDir 'server.out.log'
$StderrLog = Join-Path $LogDir 'server.err.log'

# Under the task, conhost --headless swallows the console, so this writes to a
# file as well. Timestamped so one start can be told from the next.
function Write-Log {
    param([string]$Message)
    $Line = '{0} {1}' -f (Get-Date -Format 's'), $Message
    Add-Content -LiteralPath $LauncherLog -Value $Line
    Write-Host $Line
}

# The JDK's version from its own `release` file (JAVA_VERSION="25.0.4"), or
# $null for anything that is not a JDK with a java.exe.
function Get-JdkVersion {
    param([string]$JdkHome)
    if (-not $JdkHome -or -not (Test-Path -LiteralPath (Join-Path $JdkHome 'bin\java.exe'))) { return $null }
    $Release = Join-Path $JdkHome 'release'
    if (-not (Test-Path -LiteralPath $Release)) { return $null }
    $Match = Select-String -LiteralPath $Release -Pattern '^JAVA_VERSION="([0-9]+(?:\.[0-9]+)*)' | Select-Object -First 1
    if (-not $Match) { return $null }
    $Text = $Match.Matches[0].Groups[1].Value
    if ($Text -notmatch '\.') { $Text += '.0' }  # "25" alone is no [Version]
    try { return [Version]$Text } catch { return $null }
}

# Ghidra 12.2 needs JDK 25 or newer, and the environment cannot be trusted to
# name one: here the user-scope JAVA_HOME is a JDK 8 that shadows the
# machine-scope one the Temurin MSI maintains, and PATH's java.exe is Oracle's
# Java 8 shim. So the newest JDK of 25+ actually present wins, out of the
# machine-scope JAVA_HOME and every JDK under Eclipse Adoptium (100-winget
# installs Temurin 25 there). Resolved at every start, as in
# languagetool-server.ps1: each Temurin upgrade moves to a fresh versioned
# directory and empties the old one.
function Resolve-Jdk {
    $Candidates = @([Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine'))
    $Adoptium = Join-Path $env:ProgramFiles 'Eclipse Adoptium'
    $Candidates += @(Get-ChildItem -LiteralPath $Adoptium -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $Best = $null
    $BestVersion = $null
    foreach ($Candidate in $Candidates) {
        $Version = Get-JdkVersion $Candidate
        if ($Version -and $Version.Major -ge 25 -and (-not $BestVersion -or $Version -gt $BestVersion)) {
            $Best = $Candidate
            $BestVersion = $Version
        }
    }
    if (-not $Best) {
        throw "no JDK 25 or newer found (machine JAVA_HOME, $Adoptium). Is EclipseAdoptium.Temurin.25.JDK installed (100-winget)?"
    }
    return $Best
}

# Ghidra comes from scoop (200-scoop-install), whose manifest points the
# user-scope GHIDRA_INSTALL_DIR at apps\ghidra\current. The junction is
# resolved to its versioned directory here, so that `scoop update` (210, every
# apply) re-pointing it under a running server cannot mix two Ghidra versions'
# jars in one JVM: this process keeps the version it started with, which scoop
# leaves on disk, and the next start takes the new one.
function Resolve-Ghidra {
    $Current = Join-Path $ScoopRoot 'apps\ghidra\current'
    if (-not (Test-Path -LiteralPath $Current)) {
        throw "$Current not found -- is scoop's ghidra installed (200-scoop-install)?"
    }
    $Item = Get-Item -LiteralPath $Current
    # Target is a string[] in Windows PowerShell 5.1 and a string in pwsh 7.
    $Dir = if ($Item.LinkType -and $Item.Target) { @($Item.Target)[0] } else { $Item.FullName }
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'support\launch.properties'))) {
        throw "$Dir is not a Ghidra installation (no support\launch.properties)"
    }
    return $Dir
}

# uv's tool shims live wherever UV_TOOL_BIN_DIR says (scoop persists them);
# PATH is the fallback for a uv left at its defaults.
function Resolve-Server {
    $BinDir = [Environment]::GetEnvironmentVariable('UV_TOOL_BIN_DIR', 'User')
    if ($BinDir) {
        $Exe = Join-Path $BinDir 'pyghidra-mcp.exe'
        if (Test-Path -LiteralPath $Exe) { return $Exe }
    }
    $OnPath = Get-Command pyghidra-mcp.exe -ErrorAction SilentlyContinue
    if ($OnPath) { return $OnPath.Source }
    throw 'pyghidra-mcp.exe not found -- is it installed (500-python, .chezmoidata/python-tools.toml)?'
}

try {
    $Jdk = Resolve-Jdk
    $Ghidra = Resolve-Ghidra
    $Server = Resolve-Server
} catch {
    Write-Log "error: $_"
    exit 1
}

# A server left behind by an earlier instance of the task -- stopping the task
# does not reliably take the grandchildren with it (see 102-sshd-user-session)
# -- would hold both the port and the project lock. Only processes whose
# command line names this project directory are touched.
foreach ($Stale in @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pyghidra-mcp.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$DataDir*" })) {
    Write-Log "debug: reaping stale server (pid $($Stale.ProcessId))"
    Stop-Process -Id $Stale.ProcessId -Force -ErrorAction SilentlyContinue
}

$env:JAVA_HOME = $Jdk
$env:PATH = (Join-Path $Jdk 'bin') + ';' + $env:PATH
$env:GHIDRA_INSTALL_DIR = $Ghidra
# Chroma (pyghidra-mcp's search index) reports usage to PostHog unless told not
# to; it does not read DO_NOT_TRACK.
$env:ANONYMIZED_TELEMETRY = 'False'
# Output goes to files, not a console, so Python would otherwise encode it as
# cp1252 and choke on the progress bars' block characters.
$env:PYTHONUTF8 = '1'

$Arguments = '-t streamable-http -o 127.0.0.1 -p {0} --project-path "{1}" --project-name claude' -f $Port, $DataDir
Write-Log "debug: JDK $Jdk, Ghidra $Ghidra"

# This loop is the supervisor. The task's own restart-on-failure never fires:
# conhost --headless does not pass the exit code on, so the task records 0x0
# whatever the server exited with. A clean exit is taken as deliberate; a
# failure is retried a minute later, up to three in a row -- a server that ran
# for ten minutes before failing starts the count afresh.
$Failures = 0
while ($true) {
    # The previous run's output is kept beside the new one.
    foreach ($Log in $StdoutLog, $StderrLog) {
        if (Test-Path -LiteralPath $Log) { Move-Item -LiteralPath $Log -Destination "$Log.1" -Force }
    }

    Write-Log "debug: exec $Server $Arguments"
    $Started = Get-Date
    # From the project directory, so anything pyghidra-mcp resolves relative
    # to the working directory lands beside the project, not in System32.
    $Proc = Start-Process -FilePath $Server -ArgumentList $Arguments -WorkingDirectory $DataDir `
        -NoNewWindow -PassThru -RedirectStandardOutput $StdoutLog -RedirectStandardError $StderrLog
    # Touching Handle keeps ExitCode readable after WaitForExit; without it
    # Start-Process's Process object reports $null.
    $null = $Proc.Handle
    $Proc.WaitForExit()
    $Code = $Proc.ExitCode

    if ($Code -eq 0) {
        Write-Log 'notice: server exited cleanly'
        exit 0
    }
    if (((Get-Date) - $Started).TotalMinutes -ge 10) { $Failures = 0 }
    $Failures++
    if ($Failures -ge 3) {
        Write-Log "error: server exited with $Code, the third failure in a row; giving up until the next logon or apply (see $StderrLog)"
        exit $Code
    }
    Write-Log "warning: server exited with $Code; restarting in a minute (failure $Failures of 3)"
    Start-Sleep -Seconds 60
}
