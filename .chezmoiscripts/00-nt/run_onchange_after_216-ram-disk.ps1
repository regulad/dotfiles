# The RAM disk at E:: a RamDyn disk (AIM Toolkit, which 200-scoop-install
# installs from the regulad bucket) of up to half the memory Windows sees,
# created at every boot by the MountRamDisk task registered here.
#
# RamDyn keeps the disk's contents in its own memory, allocated as blocks are
# written and given back when NTFS TRIMs them on delete, so the size is a
# ceiling rather than a reservation: an empty disk costs RamDyn about 16 MB.
# Measured on the Z13 on 2026-11-22: writing 2 GiB took RamDyn from 17 to
# 2,070 MB, and deleting it brought it back to 18 MB within 15 s. The contents
# last as long as RamDyn runs, so until shutdown or restart; hibernation keeps
# them, by writing them into hiberfil.sys.
#
# x64 Windows only, and natively: the Arsenal Image Mounter driver has no
# ARM64 build, and a driver cannot run translated. .chezmoiignore.tmpl leaves
# this script out everywhere else, on the same gate as aim-toolkit in
# 200-scoop-install.
#
# The MountRamDisk task, at every boot, as SYSTEM:
#
# - Size: half of TotalPhysicalMemory, read at boot, so more RAM, or a
#   different share of it carved out for an iGPU, needs no re-apply.
# - Letter: E:. Another volume holding E: is moved to the first free letter
#   from F: on, as MountDevDrive (050-dev-drive) moves whatever holds D:. That
#   task now looks from F: on as well, so neither takes the other's letter.
# - Identity: RamDyn writes the disk's MBR itself, with the CRC-32 of its mount
#   point string as the disk signature and the partition at a fixed offset.
#   Windows identifies a basic MBR volume by those two, so the RAM disk is the
#   same volume to it at every boot: the same volume ID, the same E: entry in
#   MountedDevices, per-volume settings kept. (A test disk at R: was
#   {65e9c64c-0000-0000-0010-000000000000}, signature then offset.) For E: the
#   signature is 0xA827A96A, which is how this script and 055-usn-journal
#   recognise it.
# - RamDyn's arguments: TRIM (-1) rather than its timed cleanup scan;
#   ordinary pageable memory (0), since AWE or large pages would lock it into
#   RAM and need the lock-pages privilege; 1 MiB blocks (20), its default;
#   NTFS; 512-byte sectors; fixed rather than removable media.
# - RamDyn is started through WMI's Win32_Process.Create, not as the task's
#   child, so nothing Task Scheduler does to the task -- its time limit,
#   ending it from its UI -- can reach the process holding the disk.
# - Already serving E: (the task run by hand mid-session) means nothing to do:
#   running it again never touches a live disk.
# - Each boot's result goes to C:\RamDisk.log, one line, replaced every boot,
#   like C:\DevDrive.optimize.log.
# - It starts on battery and keeps running when unplugged. A task's defaults
#   are the opposite (DisallowStartIfOnBatteries and StopIfGoingOnBatteries
#   are both true), and a laptop booted unplugged would get no RAM disk.
#
# The apply side is run_onchange_, like 050-dev-drive and
# 215-languagetool-service: an unelevated user cannot read a SYSTEM task back,
# so there is no drift check cheap enough for every apply, and editing this
# file is what re-registers the task. The registration is one UAC prompt,
# through sudo, which is inline (registry-system.reg sets it) and so waits and
# returns the exit code. When E: is free, the task is started at once. When
# another volume holds E:, that is left to the next boot rather than moving a
# volume out from under whatever has it open, as 050-dev-drive leaves D:.

$TaskName = 'MountRamDisk'
$Letter = 'E'
$Label = 'RamDisk'
# CRC-32 of "E:" in UTF-16LE: the disk signature RamDyn gives a disk it mounts
# at E:. Converted from a string, since 0xA827A96A as a PowerShell literal is a
# negative Int32 and would never equal the UInt32 that Get-Disk reports.
$Signature = [Convert]::ToUInt32('A827A96A', 16)
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-RamDisk {
    $Disk = Get-Partition -DriveLetter $Letter -ErrorAction SilentlyContinue | Get-Disk -ErrorAction SilentlyContinue
    return [bool]($Disk -and ("$($Disk.PartitionStyle)" -eq 'MBR') -and ([uint32]$Disk.Signature -eq $Signature))
}

# config.exe, AIM Toolkit's installer, records where it installed in its
# uninstall entry: Program Files\AIM Toolkit, or a folder an earlier install
# chose. The boot script reads the same entry, so it follows an upgrade.
$Entry = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AIM-tk' -ErrorAction SilentlyContinue
$RamDyn = $null
if ($Entry -and $Entry.DisplayIcon) { $RamDyn = Join-Path (Split-Path -Parent $Entry.DisplayIcon) 'RamDyn.exe' }
if (-not $RamDyn -or -not (Test-Path -LiteralPath $RamDyn)) {
    Write-Host 'error: RamDyn.exe not found in AIM Toolkit''s install folder -- did 200-scoop-install install aim-toolkit?'
    exit 1
}

# Run by the task as SYSTEM, under Windows PowerShell. @LETTER@ and @LABEL@
# are filled in below, so the letter and label are written once, above.
$BootScript = @'
$Letter = '@LETTER@'
$Label = '@LABEL@'
$Log = 'C:\RamDisk.log'
function Write-Log([string]$Line) { Set-Content -LiteralPath $Log -Value ('{0:s} {1}' -f (Get-Date), $Line) }

$Entry = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AIM-tk' -ErrorAction SilentlyContinue
$RamDyn = $null
if ($Entry -and $Entry.DisplayIcon) { $RamDyn = Join-Path (Split-Path -Parent $Entry.DisplayIcon) 'RamDyn.exe' }
if (-not $RamDyn -or -not (Test-Path -LiteralPath $RamDyn)) { Write-Log 'no RAM disk: RamDyn.exe not found; is AIM Toolkit installed?'; exit 1 }

if (Get-CimInstance Win32_Process -Filter "Name='RamDyn.exe'" | Where-Object { $_.CommandLine -match " $($Letter): " }) { exit 0 }

# Half of the memory Windows sees, in whole MiB, as KiB, RamDyn's unit.
$Kb = [long][math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 2 / 1MB) * 1024

$Moved = ''
$Taken = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($Letter):'"
if ($Taken) {
    $Free = 70..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Get-CimInstance Win32_Volume -Filter "DriveLetter='$($_):'") } | Select-Object -First 1
    if (-not $Free) { Write-Log "no RAM disk: $($Letter): is taken and no letter from F: on is free"; exit 1 }
    Set-CimInstance -InputObject $Taken -Property @{ DriveLetter = "$($Free):" }
    $Moved = "; moved '$($Taken.Label)' from $($Letter): to $($Free):"
}

$Command = '"{0}" {1}: {2} -1 0 20 /fs:ntfs {3} 512 0' -f $RamDyn, $Letter, $Kb, $Label
$Created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $Command }
if ($Created.ReturnValue -ne 0) { Write-Log "no RAM disk: Win32_Process.Create returned $($Created.ReturnValue) for RamDyn$Moved"; exit 1 }

$Deadline = (Get-Date).AddSeconds(120)
do {
    Start-Sleep -Seconds 1
    $Volume = Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue
} until (($Volume -and $Volume.FileSystemLabel -eq $Label) -or ((Get-Date) -gt $Deadline))
if ($Volume -and $Volume.FileSystemLabel -eq $Label) {
    Write-Log ('RAM disk at {0}: of up to {1:N1} GiB, half of RAM, RamDyn PID {2}{3}' -f $Letter, ($Kb / 1MB), $Created.ProcessId, $Moved)
} else {
    Write-Log ('RamDyn (PID {0}) started, but {1}: did not appear within 120 s{2}' -f $Created.ProcessId, $Letter, $Moved)
    exit 1
}
'@
$BootScript = $BootScript.Replace('@LETTER@', $Letter).Replace('@LABEL@', $Label)
$EncodedBoot = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($BootScript))

# Start it now only onto a free E:. A mapped network drive at E: is per logon
# session, invisible to SYSTEM, and would hide the RAM disk from this session.
$StartNow = $false
$Network = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Letter):' AND DriveType=4" -ErrorAction SilentlyContinue
if ($Network) {
    Write-Host "warning: ${Letter}: is mapped to $($Network.ProviderName) in this session, which hides the RAM disk here; map the share to another letter"
}
if (Test-RamDisk) {
    Write-Host "debug: the RAM disk is already at ${Letter}:; the new task definition applies from the next boot"
} elseif (Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue) {
    $Holder = Get-Volume -DriveLetter $Letter
    Write-Host "notice: ${Letter}: is held by '$($Holder.FileSystemLabel)'; the RAM disk appears at the next boot, when $TaskName moves that volume to the first free letter from F: on"
} elseif (-not $Network) {
    $StartNow = $true
}

Write-Host "debug: registering the $TaskName task$(if ($StartNow) { ' and starting it' })"
$Elevated = @(
    "`$ErrorActionPreference = 'Stop'"
    'try {'
    "    `$Action = New-ScheduledTaskAction -Execute '$PowerShell' -Argument '-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $EncodedBoot'"
    '    $Trigger = New-ScheduledTaskTrigger -AtStartup'
    '    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)'
    "    Register-ScheduledTask -TaskName '$TaskName' -Action `$Action -Trigger `$Trigger -Settings `$Settings -RunLevel Highest -User 'SYSTEM' -Force | Out-Null"
    $(if ($StartNow) { "    Start-ScheduledTask -TaskName '$TaskName'" })
    '} catch { Write-Host (''error: '' + $_); exit 1 }'
) -join "`r`n"
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Elevated))

& sudo powershell -NoProfile -NonInteractive -EncodedCommand $Encoded
$Code = $LASTEXITCODE
if ($Code -ne 0) {
    Write-Host "error: registering the $TaskName task failed (sudo exited $Code) -- was the elevation prompt declined?"
    exit 1
}

if (-not $StartNow) {
    Write-Host "notice: $TaskName registered; it creates the RAM disk at ${Letter}: at every boot"
    exit 0
}

$Deadline = (Get-Date).AddSeconds(150)
while (-not (Test-RamDisk) -and ((Get-Date) -lt $Deadline)) { Start-Sleep -Seconds 1 }
if (-not (Test-RamDisk)) {
    $Last = Get-Content -LiteralPath 'C:\RamDisk.log' -ErrorAction SilentlyContinue
    Write-Host "error: $TaskName ran, but no RAM disk is at ${Letter}: after 150 s; C:\RamDisk.log says: $Last"
    exit 1
}
$Size = (Get-Volume -DriveLetter $Letter).Size
Write-Host ('notice: RAM disk at {0}: of up to {1:N1} GiB; {2} recreates it at every boot' -f $Letter, ($Size / 1GB), $TaskName)
