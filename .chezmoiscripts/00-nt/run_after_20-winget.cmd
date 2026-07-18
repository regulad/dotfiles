@echo off
setlocal enabledelayedexpansion

echo debug: installing winget packages
REM Install/update winget packages
set winget_packages=^
WireGuard.WireGuard ^
KDE.KDEConnect ^
Ollama.Ollama ^
NirSoft.ShellExView ^
NirSoft.USBDeview ^
Microsoft.Sysinternals.ProcessExplorer ^
UrBackup.UrBackup.Client ^
qBittorrent.qBittorrent ^
Logseq.Logseq ^
Anthropic.ClaudeCode ^
Telerik.Fiddler.Classic ^
WiresharkFoundation.Wireshark ^
Microsoft.WindowsTerminal ^
Element.Element ^
JetBrains.Toolbox ^
Zoom.Zoom.EXE ^
PrismLauncher.PrismLauncher ^
OpenWhisperSystems.Signal ^
Bitwarden.Bitwarden ^
Jellyfin.JellyfinMediaPlayer ^
Anthropic.Claude ^
WinSCP.WinSCP ^
GnuPG.GnuPG ^
MHNexus.HxD ^
VideoLAN.VLC ^
Prusa3D.PrusaSlicer ^
PuTTY.PuTTY ^
REALiX.HWiNFO ^
VB-Audio.Voicemeeter.Potato ^
9PB2MZ1ZMB1S ^
9NP83LWLPZ9K ^
9PC3H3V7Q9CH ^
EclipseAdoptium.Temurin.25.JDK ^
EclipseAdoptium.Temurin.21.JDK ^
OpenJS.NodeJS.LTS ^
Vencord.Vesktop ^
DenoLand.Deno ^
Microsoft.VisualStudioCode ^
TeamViewer.TeamViewer ^
Microsoft.PowerShell ^
Mozilla.Firefox ^
WinFsp.WinFsp ^
Microsoft.Sysinternals.Suite ^
dotPDN.PaintDotNet ^
GlavSoft.TightVNC ^
Autodesk.Fusion360 ^
Wakatime.DesktopWakatime ^
Logitech.GHUB ^
Adobe.Acrobat.Reader.64-bit ^
7zip.7zip ^
Audacity.Audacity ^
CrystalDewWorld.CrystalDiskInfo ^
CrystalDewWorld.CrystalDiskMark ^
Docker.DockerDesktop ^
Mozilla.Thunderbird ^
Notepad++.Notepad++ ^
Meta.Oculus ^
Parsec.Parsec ^
LizardByte.Sunshine ^
winaero.tweaker ^
darktable.darktable ^
Nextcloud.NextcloudDesktop ^
calibre.calibre ^
Google.GoogleDrive ^
Oracle.VirtualBox ^
WinDirStat.WinDirStat ^
IDRIX.VeraCrypt ^
Tailscale.Tailscale ^
Inkscape.Inkscape ^
angryziber.AngryIPScanner ^
Google.Chrome.EXE ^
HandBrake.HandBrake ^
LIGHTNINGUK.ImgBurn ^
OBSProject.OBSStudio ^
Libretro.RetroArch ^
Valve.Steam ^
eliboa.TegraRcmGUI ^
KDE.Kdenlive ^
EpicGames.EpicGamesLauncher ^
TexasInstruments.TIConnect ^
MoonlightGameStreamingProject.Moonlight ^
BillStewart.SyncthingWindowsSetup

REM following winget packages are not installed even though I would like them:
REM Syncthing.Syncthing - doesn't install GUI; billstewart version is psuedo-official and is used instead

for %%p in (%winget_packages%) do (
    call winget list --id %%p --exact >nul 2>&1
    if !errorLevel! == 0 (
        echo debug: winget updating %%p...
        call winget upgrade --id %%p --silent --accept-source-agreements --accept-package-agreements
    ) else (
        echo debug: winget installing %%p...
        call winget install --id %%p --silent --accept-source-agreements --accept-package-agreements
    )
)
call refreshenv >nul 2>&1

