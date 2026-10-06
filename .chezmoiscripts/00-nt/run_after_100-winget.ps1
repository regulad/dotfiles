# Declared winget packages: installs each one that is missing and upgrades each
# one that is present, on every apply.
#
# Except a portable package -- a bare exe or an archive, with no installer of
# its own -- while something of it runs. winget upgrades one by unregistering
# the commands it registered for it, then deleting its files, then laying the
# new version down. Windows refuses to delete an exe while it runs, whatever
# the delete flags, so with one running the upgrade stops after the commands
# are gone: on 2026-10-03 that took `claude` off PATH under open Claude Code
# sessions and left it on the old version besides. So before touching an
# installed package, this looks up the commands winget registered for it and
# any process running the files behind them, and leaves the package alone for
# this apply if it finds one. Packages with a real installer (MSI, MSIX, a
# setup .exe) have no commands of winget's: they put their own executables on
# PATH and cope with being upgraded while running, so they are never held back.

$WingetPackages = @(
    # Interactive `codex` fails from this package since 0.157.1 ("the CLI
    # package does not match this platform or executable"): its flat layout is
    # not one the background server can install itself from. `codex
    # --no-daemon` works meanwhile; https://github.com/openai/codex/issues/48366
    'OpenAI.Codex'
    'uvncbvba.UltraVNC'
    'Swift.Toolchain'
    'Posit.RStudio'
    'dorssel.usbipd-win'
    'Apple.AppleMobileDeviceSupport'
    'KhronosGroup.VulkanSDK'
    'ETHZurich.SafeExamBrowser'
    'WireGuard.WireGuard'
    'NirSoft.ShellExView'
    'NirSoft.USBDeview'
    'UrBackup.UrBackup.Client'
    'qBittorrent.qBittorrent'
    'Logseq.Logseq'
    'Telerik.Fiddler.Classic'
    'WiresharkFoundation.Wireshark'
    'Microsoft.WindowsTerminal'
    'Element.Element'
    'JetBrains.Toolbox'
    'Zoom.Zoom.EXE'
    'PrismLauncher.PrismLauncher'
    'OpenWhisperSystems.Signal'
    'Bitwarden.Bitwarden'
    'Jellyfin.JellyfinMediaPlayer'
    'Anthropic.Claude'
    'Anthropic.ClaudeCode'
    'WinSCP.WinSCP'
    'GnuPG.Gpg4win'
    'MHNexus.HxD'
    'VideoLAN.VLC'
    'Prusa3D.PrusaSlicer'
    'PuTTY.PuTTY'
    'REALiX.HWiNFO'
    'VB-Audio.Voicemeeter.Potato'
    'EclipseAdoptium.Temurin.25.JDK'
    'EclipseAdoptium.Temurin.21.JDK'
    'Microsoft.DotNet.SDK.8'
    'OpenJS.NodeJS.LTS'
    'Vencord.Vesktop'
    'Microsoft.VisualStudioCode'
    'TeamViewer.TeamViewer'
    'Microsoft.PowerShell'
    'Mozilla.Firefox'
    'WinFsp.WinFsp'
    'Microsoft.Sysinternals.Suite'
    'dotPDN.PaintDotNet'
    'GlavSoft.TightVNC'
    'Autodesk.Fusion360'
    'Wakatime.DesktopWakatime'
    'Logitech.GHUB'
    'Adobe.Acrobat.Reader.64-bit'
    '7zip.7zip'
    'Audacity.Audacity'
    'CrystalDewWorld.CrystalDiskInfo'
    'CrystalDewWorld.CrystalDiskMark'
    'Mozilla.Thunderbird'
    'Notepad++.Notepad++'
    'Meta.Oculus'
    'Parsec.Parsec'
    'winaero.tweaker'
    'Nextcloud.NextcloudDesktop'
    'calibre.calibre'
    'Google.GoogleDrive'
    'Oracle.VirtualBox'
    'WinDirStat.WinDirStat'
    'IDRIX.VeraCrypt'
    'Tailscale.Tailscale'
    'Inkscape.Inkscape'
    'Google.Chrome.EXE'
    'HandBrake.HandBrake'
    'LIGHTNINGUK.ImgBurn'
    'OBSProject.OBSStudio'
    'Libretro.RetroArch'
    'Valve.Steam'
    'eliboa.TegraRcmGUI'
    'KDE.Kdenlive'
    'EpicGames.EpicGamesLauncher'
    'TexasInstruments.TIConnect'
    'BillStewart.SyncthingWindowsSetup'
    '9PKTQ5699M62' # iCloud
    '9PC3H3V7Q9CH' # Rufus
)

# following winget packages are not installed even though I would like them:
# Syncthing.Syncthing - doesn't install GUI; billstewart version is psuedo-official and is used instead
# Docker.DockerDesktop - replaced by WSL's own wslc (115-wsl-update enforces the WSL that ships it); 105-docker-desktop-remove uninstalls it
# Microsoft.Sysinternals.ProcessExplorer - Microsoft.Sysinternals.Suite ships procexp too, and both register a `procexp` command; whichever installed last owns WinGet\Links\procexp.exe, and winget then refuses to upgrade the other ("Portable file has been modified")

$Uninstall = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
$LinkDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    (Join-Path $env:ProgramFiles 'WinGet\Links')
    (Join-Path ${env:ProgramFiles(x86)} 'WinGet\Links')
)

# The files behind the commands winget registered for an installed portable
# package. It registers them one of two ways: a symlink per command in a
# WinGet\Links directory, or, when it could not create symlinks (no Developer
# Mode), the package directory itself added to PATH
# (InstallDirectoryAddedToPath), which makes every exe at its top level a
# command. An upgrade keeps whichever form the first install used. The
# package's uninstall entry names its symlink only for a single exe -- an
# archive keeps its list in a database in the package directory -- so the Links
# directories are scanned for symlinks into the package instead.
function Get-WingetCommandTargets([string]$Id) {
    $Entries = foreach ($Hive in 'HKCU:', 'HKLM:') {
        Get-ChildItem -LiteralPath "$Hive\$Uninstall" -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName.StartsWith("$($Id)_", [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
            Where-Object { $_.WinGetPackageIdentifier -eq $Id -and $_.WinGetInstallerType -eq 'portable' -and $_.InstallLocation }
    }
    foreach ($Entry in $Entries) {
        $Dir = $Entry.InstallLocation.TrimEnd('\') + '\'
        if ($Entry.TargetFullPath) { $Entry.TargetFullPath }
        foreach ($Link in Get-ChildItem -LiteralPath $LinkDirs -ErrorAction SilentlyContinue) {
            $Target = @($Link.Target)[0]
            if ($Link.LinkType -eq 'SymbolicLink' -and $Target -and $Target.StartsWith($Dir, [StringComparison]::OrdinalIgnoreCase)) { $Target }
        }
        if ($Entry.InstallDirectoryAddedToPath -eq 1) {
            Get-ChildItem -LiteralPath $Entry.InstallLocation -Filter '*.exe' -File -ErrorAction SilentlyContinue | ForEach-Object FullName
        }
    }
}

# QueryFullProcessImageName rather than Get-Process's Path: it needs only
# limited query access, so it can read more processes, and it names the file
# actually mapped. A process started through a WinGet\Links symlink reports
# the symlink as its Path, but the package's own exe here -- the file winget
# fails to delete.
if (-not ('Dotfiles.ProcessImage' -as [type])) {
    Add-Type -Namespace Dotfiles -Name ProcessImage -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, System.Text.StringBuilder name, ref uint size);
[DllImport("kernel32.dll")]
static extern bool CloseHandle(IntPtr handle);
public static string PathOf(int pid) {
    IntPtr process = OpenProcess(0x1000 /* PROCESS_QUERY_LIMITED_INFORMATION */, false, pid);
    if (process == IntPtr.Zero) return null;
    try {
        var name = new System.Text.StringBuilder(32768);
        uint size = (uint)name.Capacity;
        return QueryFullProcessImageNameW(process, 0, name, ref size) ? name.ToString() : null;
    }
    finally { CloseHandle(process); }
}
'@
}

function Get-ProcessesRunning([string[]]$Files) {
    foreach ($Process in Get-Process) {
        $Image = [Dotfiles.ProcessImage]::PathOf($Process.Id)
        # -contains compares strings case-insensitively, as Windows paths are.
        if ($Image -and $Files -contains $Image) {
            [pscustomobject]@{ Id = $Process.Id; Name = Split-Path -Leaf $Image }
        }
    }
}

Write-Host 'debug: installing winget packages'
foreach ($Package in $WingetPackages) {
    & winget list --id $Package --exact *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "debug: winget installing $Package..."
        & winget install --id $Package --silent --accept-source-agreements --accept-package-agreements
        continue
    }

    $Targets = @(Get-WingetCommandTargets $Package | Sort-Object -Unique)
    $Running = @(if ($Targets.Count) { Get-ProcessesRunning $Targets })
    if ($Running.Count) {
        $Names = ($Running | ForEach-Object Name | Sort-Object -Unique) -join ', '
        $Ids = ($Running | ForEach-Object Id) -join ', '
        Write-Host "warning: not touching $Package while $Names is running (PID $Ids): winget would unregister its commands, then fail to replace the running exe; close it and apply again"
        continue
    }

    Write-Host "debug: winget updating $Package..."
    & winget upgrade --id $Package --silent --accept-source-agreements --accept-package-agreements
}
