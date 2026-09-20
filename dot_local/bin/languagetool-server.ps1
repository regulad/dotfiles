# THIS FILE IS MANAGED BY CHEZMOI!
#
# Launcher for the LanguageTool HTTP server. This is what the NSSM-supervised
# `LanguageTool` Windows service executes -- registered by
# .chezmoiscripts/00-nt/215-languagetool-service.ps1 -- and it is also runnable
# by hand, which is the easiest way to watch the thing start:
#
#     .local\bin\languagetool-server.ps1 -Jar scoop\apps\languagetool-java\current\languagetool-server.jar
#
# The service used to point NSSM straight at java.exe, and it cannot. The JDK
# comes from winget (100-winget: EclipseAdoptium.Temurin.21.JDK), and every
# Temurin upgrade installs into a fresh versioned directory --
# C:\Program Files\Eclipse Adoptium\jdk-<version>-hotspot -- and empties the
# previous one. A service registered against one of those paths is therefore
# broken by the next JDK update, and stays broken until someone notices:
# observed on 2026-09-19 with the service dead since at least the 15th, two
# emptied jdk-21.0.x directories behind the one it was pointed at, and nssm
# logging "CreateProcess() failed: The system cannot find the file specified"
# to the Application event log on every boot. NSSM does not expand environment
# variables in its Application value, so `%JAVA_HOME%\bin\java.exe` is not a
# way out either. Resolving java at every start is.
#
# This runs as LocalSystem under the SCM, so nothing here may lean on the
# user's environment: no $HOME, no user-scope variables, no user PATH. The jar
# and the port are passed in by the registration script for exactly that
# reason. JAVA_HOME *is* consulted, but only the machine-scope one the Temurin
# MSI maintains, and only as a preference -- see Resolve-Java.

param(
    # The languagetool-server.jar to run. Passed rather than discovered so the
    # registration script is the only thing that knows where scoop lives.
    [Parameter(Mandatory = $true)]
    [string]$Jar,
    [int]$Port = 8081
)

$ErrorActionPreference = 'Stop'

# Everything goes to stdout, which NSSM redirects into the service log (see
# AppStdout in the registration script). Without a timestamp the log cannot
# tell one start from the next.
function Write-Log {
    param([string]$Message)
    Write-Host ("{0} {1}" -f (Get-Date -Format 's'), $Message)
}

# Picks a java.exe, in this order:
#
#   1. %JAVA_HOME%\bin\java.exe, if that file exists. The Temurin MSI keeps the
#      machine-scope JAVA_HOME pointed at whatever it installed last, so this is
#      the normal case and it tracks upgrades on its own.
#   2. The newest JDK actually present under C:\Program Files\Eclipse Adoptium.
#      This is the case JAVA_HOME cannot cover: the SCM hands a service the
#      environment block as of boot, so right after an in-session upgrade
#      JAVA_HOME can still name the directory that was just emptied.
#   3. Whatever `java.exe` the machine PATH resolves, as a last resort.
#
# LanguageTool 6.x needs Java 17 or newer; every JDK winget installs here
# qualifies, so there is no minimum-version check.
function Resolve-Java {
    if ($env:JAVA_HOME) {
        $FromHome = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path -LiteralPath $FromHome) {
            return $FromHome
        }
        Write-Log "warning: JAVA_HOME=$($env:JAVA_HOME) has no bin\java.exe (stale after a JDK upgrade?); falling back"
    }

    $Adoptium = Join-Path $env:ProgramFiles 'Eclipse Adoptium'
    $Installed = @(Get-ChildItem -LiteralPath $Adoptium -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe') } |
        Sort-Object -Descending -Property @{ Expression = {
            # jdk-21.0.12.101-hotspot -> 21.0.12.101. Anything that does not
            # parse sorts last rather than throwing.
            $v = [Version]'0.0'
            if ($_.Name -match '^jdk-(\d+(?:\.\d+)+)') {
                try { $v = [Version]$Matches[1] } catch { }
            }
            $v
        } }, Name)
    if ($Installed.Count -gt 0) {
        return (Join-Path $Installed[0].FullName 'bin\java.exe')
    }

    $OnPath = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($OnPath) {
        return $OnPath.Source
    }

    throw "no java.exe found: JAVA_HOME is '$($env:JAVA_HOME)', nothing installed under $Adoptium, nothing on PATH. Is EclipseAdoptium.Temurin.21.JDK installed (100-winget)?"
}

if (-not (Test-Path -LiteralPath $Jar)) {
    throw "$Jar not found -- is languagetool-java installed (200-scoop-install)?"
}

$Java = Resolve-Java
Write-Log "using $Java"
Write-Log "exec java -cp $Jar org.languagetool.server.HTTPServer --port $Port --allow-origin *"

# Invoked through ProcessStartInfo with an explicit argument *string* rather
# than as `& $Java ... --allow-origin '*'`, for the same reason the sshd
# launcher's ssh-keygen call is: what reaches java.exe has to be exactly
# `--allow-origin "*"`, quotes included, and PowerShell cannot be trusted to
# produce that. java.exe's Windows launcher expands an unquoted `*` against
# the working directory itself -- observed in a dry run: the server came up
# with `WARNING: unknown option: .chezmoidata` for every entry in the cwd and
# the origin set to the first filename. Whether PowerShell quotes the token is
# host-dependent (5.1 passes `"*"` through, 7.3+ escapes it to `\"*\"`), and
# the service runs under 5.1 while a hand run may be under pwsh. An explicit
# Arguments string goes verbatim to CreateProcess in either.
#
# No redirection: with UseShellExecute off and nothing redirected, java
# inherits this process's stdout and stderr, which NSSM points at the service
# log. Routing them through PowerShell would turn every stderr line into a
# NativeCommandError with a stack trace attached.
#
# No --public: the server binds loopback only, which is all the editor
# integrations that talk to it need.
#
# WaitForExit keeps this in the foreground for the life of java: NSSM
# supervises the process it started, so returning early would make the service
# look up while the server was still coming up, and look up while it was dead.
$Psi = New-Object System.Diagnostics.ProcessStartInfo
$Psi.FileName = $Java
$Psi.Arguments = '-cp "' + $Jar + '" org.languagetool.server.HTTPServer --port ' + $Port + ' --allow-origin "*"'
$Psi.UseShellExecute = $false
$Proc = [System.Diagnostics.Process]::Start($Psi)
$Proc.WaitForExit()

exit $Proc.ExitCode
