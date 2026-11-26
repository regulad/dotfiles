# The RAM disk at E:: a RamDyn disk (AIM Toolkit, which 200-scoop-install
# installs from the regulad bucket) of up to half the memory Windows sees,
# created at every boot by the MountRamDisk task registered here, with an
# E:\Temp private to the account that applied this, which 217-ram-disk-temp
# points that account's TEMP and TMP at.
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
# this script and 217 out everywhere else, on the same gate as aim-toolkit in
# 200-scoop-install.
#
# The MountRamDisk task, at every boot, as SYSTEM:
#
# - Size: half of TotalPhysicalMemory, read at boot, so more RAM, or a
#   different share of it carved out for an iGPU, needs no re-apply.
# - Letter: E:. Another volume holding E: is moved to the first free letter
#   from F: on, as MountDevDrive (050-dev-drive) moves whatever holds D:. That
#   task looks from F: on as well, so neither takes the other's letter.
# - Identity: RamDyn writes the disk's MBR itself, with the CRC-32 of its mount
#   point string as the disk signature and the partition at a fixed offset.
#   Windows identifies a basic MBR volume by those two, so the RAM disk is the
#   same volume to it at every boot: volume ID
#   {a827a96a-0000-0000-0010-000000000000}, signature then offset, the same E:
#   entry in MountedDevices, per-volume settings kept. The signature for E:,
#   0xA827A96A, is how this script and 055-usn-journal recognise it.
# - RamDyn's arguments: TRIM (-1) rather than its timed cleanup scan;
#   ordinary pageable memory (0), since AWE or large pages would lock it into
#   RAM and need the lock-pages privilege; 1 MiB blocks (20), its default;
#   NTFS; 512-byte sectors; fixed rather than removable media.
# - RamDyn is started through WMI's Win32_Process.Create, not as the task's
#   child, so nothing Task Scheduler does to the task -- its time limit,
#   ending it from its UI -- can reach the process holding the disk.
# - E:\Temp: private to one account, SYSTEM and Administrators, rather than
#   E:'s root, which every signed-in user may write to as format leaves it,
#   and which holds System Volume Information. One account, because these
#   machines are single-user: the SID of whoever applied this is written
#   into the boot script, so the last account to apply it owns E:\Temp.
# - Already serving E: (the task run by hand, or by an apply) means only
#   E:\Temp is seen to: running it again never touches a live disk.
# - Fallback: should RamDyn be missing or fail, E: is mapped to
#   C:\RamDisk.fallback, emptied first, with the same E:\Temp, so a TEMP
#   pointing there still works, from C:. DefineDosDevice, called as
#   LocalSystem, defines the letter for every session. A fallback from an
#   earlier run is removed before the next try, so the RAM disk gets the
#   letter back.
# - Each run's result goes to the Application event log, source MountRamDisk,
#   which the task registers: event 1 the RAM disk is up, 2 the fallback is,
#   3 neither. No file: nothing a task writes goes in C:\. The latest:
#   Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'MountRamDisk' } -MaxEvents 1
# - It starts on battery and keeps running when unplugged. A task's defaults
#   are the opposite (DisallowStartIfOnBatteries and StopIfGoingOnBatteries
#   are both true), and a laptop booted unplugged would get no RAM disk.
#
# The apply side is run_onchange_, like 050-dev-drive and
# 215-languagetool-service: an unelevated user cannot read a SYSTEM task back,
# so there is no drift check cheap enough for every apply, and editing this
# file is what re-registers the task. The registration is one UAC prompt,
# through sudo, which is inline (registry-system.reg sets it) and so waits and
# returns the exit code. The task is then run at once, unless another volume
# holds E:: moving a volume out from under whatever has it open is left to the
# next boot, as 050-dev-drive leaves D:.

$TaskName = 'MountRamDisk'
$Letter = 'E'
$Label = 'RamDisk'
# CRC-32 of "E:" in UTF-16LE: the disk signature RamDyn gives a disk it mounts
# at E:. Converted from a string, since 0xA827A96A as a PowerShell literal is a
# negative Int32 and would never equal the UInt32 that Get-Disk reports.
$Signature = [Convert]::ToUInt32('A827A96A', 16)
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$TempDir = "${Letter}:\Temp"
# The one account E:\Temp is for: whoever applies this.
$MySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

# E:\Temp is there, this account has access to it, and nobody but this
# account, SYSTEM and Administrators has any.
function Test-TempFolder {
    $Acl = Get-Acl -LiteralPath $TempDir -ErrorAction SilentlyContinue
    if (-not $Acl) { return $false }
    $Sids = @($Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value })
    $Others = @($Sids | Where-Object { $_ -notin @($MySid, 'S-1-5-18', 'S-1-5-32-544') })
    return (($Sids -contains $MySid) -and ($Others.Count -eq 0))
}

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

# Run by the task as SYSTEM, under Windows PowerShell, which has the
# *-EventLog cmdlets PowerShell 7 dropped. @LETTER@, @LABEL@, @SID@ and @TASK@
# are filled in below, so each is written once, above.
$BootScript = @'
$Letter = '@LETTER@'
$Label = '@LABEL@'
$Owner = '@SID@'
$Source = '@TASK@'
$Fallback = 'C:\RamDisk.fallback'
# Each run's result, to the Application event log: 1 the RAM disk is up, 2 the
# fallback is, 3 neither.
if (-not [Diagnostics.EventLog]::SourceExists($Source)) { New-EventLog -LogName Application -Source $Source }
function Write-Log([string]$Line, [int]$Id = 1) {
    $Type = @{ 1 = 'Information'; 2 = 'Warning'; 3 = 'Error' }[$Id]
    Write-EventLog -LogName Application -Source $Source -EventId $Id -EntryType $Type -Message $Line
}

Add-Type -Namespace RamDisk -Name Dos -MemberDefinition @"
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool DefineDosDeviceW(uint flags, string device, string target);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint QueryDosDeviceW(string device, System.Text.StringBuilder target, int max);
"@

# E:\Temp, private to $Owner, SYSTEM and Administrators: inheritance from the
# root cut, those three granted, and Authenticated Users and Users, which the
# root's ACL hands down, removed should they be there explicitly.
function Set-TempFolder {
    $Temp = "$($Letter):\Temp"
    New-Item -ItemType Directory -Force -Path $Temp | Out-Null
    & icacls.exe $Temp /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*$($Owner):(OI)(CI)F" | Out-Null
    & icacls.exe $Temp /remove:g '*S-1-5-11' '*S-1-5-32-545' | Out-Null
}

# E: on C:\RamDisk.fallback instead, emptied, with the same E:\Temp.
function Use-Fallback([string]$Why) {
    if (Get-CimInstance Win32_Volume -Filter "DriveLetter='$($Letter):'") { Write-Log "no RAM disk: $Why; $($Letter): is another volume, so no fallback either" 3; exit 1 }
    if (Test-Path -LiteralPath $Fallback) { Remove-Item -LiteralPath $Fallback -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $Fallback | Out-Null
    if (-not [RamDisk.Dos]::DefineDosDeviceW(0, "$($Letter):", $Fallback)) {
        Write-Log ("no RAM disk: $Why; mapping $($Letter): to $Fallback failed too (Win32 error {0})" -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) 3
        exit 1
    }
    Set-TempFolder
    Write-Log "no RAM disk: $Why; $($Letter): is $Fallback instead, with $($Letter):\Temp" 2
    exit 1
}

# A fallback from an earlier run goes first, so the RAM disk can take E:.
$Target = New-Object System.Text.StringBuilder 1024
if (([RamDisk.Dos]::QueryDosDeviceW("$($Letter):", $Target, 1024) -gt 0) -and ($Target.ToString() -like "*$Fallback")) {
    [void][RamDisk.Dos]::DefineDosDeviceW(2, "$($Letter):", $null)
}

$Entry = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AIM-tk' -ErrorAction SilentlyContinue
$RamDyn = $null
if ($Entry -and $Entry.DisplayIcon) { $RamDyn = Join-Path (Split-Path -Parent $Entry.DisplayIcon) 'RamDyn.exe' }
if (-not $RamDyn -or -not (Test-Path -LiteralPath $RamDyn)) { Use-Fallback 'RamDyn.exe not found; is AIM Toolkit installed?' }

$Serving = Get-CimInstance Win32_Process -Filter "Name='RamDyn.exe'" | Where-Object { $_.CommandLine -match " $($Letter): " } | Select-Object -First 1
if ($Serving) {
    Set-TempFolder
    Write-Log "RAM disk already at $($Letter):, RamDyn PID $($Serving.ProcessId); $($Letter):\Temp seen to"
    exit 0
}

# Half of the memory Windows sees, in whole MiB, as KiB, RamDyn's unit.
$Kb = [long][math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 2 / 1MB) * 1024

$Moved = ''
$Taken = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($Letter):'"
if ($Taken) {
    $Free = 70..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Get-CimInstance Win32_Volume -Filter "DriveLetter='$($_):'") } | Select-Object -First 1
    if (-not $Free) { Write-Log "no RAM disk: $($Letter): is taken and no letter from F: on is free" 3; exit 1 }
    Set-CimInstance -InputObject $Taken -Property @{ DriveLetter = "$($Free):" }
    $Moved = "; moved '$($Taken.Label)' from $($Letter): to $($Free):"
}

$Command = '"{0}" {1}: {2} -1 0 20 /fs:ntfs {3} 512 0' -f $RamDyn, $Letter, $Kb, $Label
$Created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $Command }
if ($Created.ReturnValue -ne 0) { Use-Fallback "Win32_Process.Create returned $($Created.ReturnValue) for RamDyn$Moved" }

$Deadline = (Get-Date).AddSeconds(120)
do {
    Start-Sleep -Seconds 1
    $Volume = Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue
} until (($Volume -and $Volume.FileSystemLabel -eq $Label) -or ((Get-Date) -gt $Deadline))
if (-not ($Volume -and $Volume.FileSystemLabel -eq $Label)) {
    Stop-Process -Id $Created.ProcessId -Force -ErrorAction SilentlyContinue
    Use-Fallback "RamDyn (PID $($Created.ProcessId)) started, but $($Letter): did not appear within 120 s$Moved"
}
Set-TempFolder
Write-Log ('RAM disk at {0}: of up to {1:N1} GiB, half of RAM, RamDyn PID {2}{3}; with {0}:\Temp' -f $Letter, ($Kb / 1MB), $Created.ProcessId, $Moved)
'@
$BootScript = $BootScript.Replace('@LETTER@', $Letter).Replace('@LABEL@', $Label).Replace('@SID@', $MySid).Replace('@TASK@', $TaskName)

# Run it now, unless another volume holds E:. A mapped network drive at E: is
# per logon session, invisible to SYSTEM, and would hide the RAM disk from
# this session.
$StartNow = $false
$Network = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Letter):' AND DriveType=4" -ErrorAction SilentlyContinue
if ($Network) {
    Write-Host "warning: ${Letter}: is mapped to $($Network.ProviderName) in this session, which hides the RAM disk here; map the share to another letter"
} elseif ((-not (Test-RamDisk)) -and (Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue)) {
    $Holder = Get-Volume -DriveLetter $Letter
    Write-Host "notice: ${Letter}: is held by '$($Holder.FileSystemLabel)'; the RAM disk appears at the next boot, when $TaskName moves that volume to the first free letter from F: on"
} else {
    $StartNow = $true
}

Write-Host "debug: registering the $TaskName task$(if ($StartNow) { ' and running it' })"
# The boot script rides in the elevated script as text, in a here-string, and
# is encoded for the task's -EncodedCommand on the elevated side. Encoded here
# instead, it would be UTF-16 base64 inside UTF-16 base64, about 7 times its
# own length, and the sudo command line would near Windows' 32,767 characters.
# The boot script has no line starting with '@, so it cannot end the
# here-string early.
# No progress records: Windows PowerShell with its output redirected writes
# them to stderr as CLIXML, the scheduled-task cmdlets emit some, and
# PowerShell 7 upstream prints "Cannot process the XML from the 'Error'
# stream" for each.
$Elevated = @(
    "`$ErrorActionPreference = 'Stop'"
    "`$ProgressPreference = 'SilentlyContinue'"
    "`$BootScript = @'"
    $BootScript.TrimEnd()
    "'@"
    '$EncodedBoot = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($BootScript))'
    'try {'
    "    `$Action = New-ScheduledTaskAction -Execute '$PowerShell' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ' + `$EncodedBoot)"
    '    $Trigger = New-ScheduledTaskTrigger -AtStartup'
    '    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)'
    "    Register-ScheduledTask -TaskName '$TaskName' -Action `$Action -Trigger `$Trigger -Settings `$Settings -RunLevel Highest -User 'SYSTEM' -Force | Out-Null"
    $(if ($StartNow) { "    Start-ScheduledTask -TaskName '$TaskName'" })
    '} catch { Write-Host (''error: '' + $_); exit 1 }'
) -join "`r`n"
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Elevated))

$Started = Get-Date
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

# Done once the task has logged its run since sudo was started, and E:\Temp
# is as it should be, on the RAM disk or the fallback. E:\Temp being there is
# not enough: an earlier run may have left it. The Application log is readable
# unelevated.
function Get-RunEvent {
    param([Nullable[datetime]]$Since)
    $Filter = @{ LogName = 'Application'; ProviderName = $TaskName }
    if ($Since) { $Filter.StartTime = $Since }
    Get-WinEvent -FilterHashtable $Filter -MaxEvents 1 -ErrorAction SilentlyContinue
}
$Deadline = (Get-Date).AddSeconds(150)
while (-not ((Get-RunEvent $Started) -and (Test-TempFolder)) -and ((Get-Date) -lt $Deadline)) { Start-Sleep -Seconds 1 }
$Run = Get-RunEvent $Started
if (-not $Run) {
    Write-Host "error: $TaskName did not finish within 150 s; its last event says: $((Get-RunEvent).Message)"
    exit 1
}
if (-not (Test-TempFolder)) {
    Write-Host "error: $TaskName ran, but $TempDir is missing or open to other accounts; it says: $($Run.Message)"
    exit 1
}
if (-not (Test-RamDisk)) {
    Write-Host "warning: no RAM disk; ${Letter}: is the fallback on C:. $TaskName says: $($Run.Message)"
    exit 1
}
$Size = (Get-Volume -DriveLetter $Letter).Size
Write-Host ('notice: RAM disk at {0}: of up to {1:N1} GiB, with {2}; {3} recreates both at every boot' -f $Letter, ($Size / 1GB), $TempDir, $TaskName)
