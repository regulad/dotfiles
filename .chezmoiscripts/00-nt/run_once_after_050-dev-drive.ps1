# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
  if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
    $CommandLine = "-NoExit -File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
    Start-Process -Wait -FilePath powershell.exe -Verb Runas -ArgumentList $CommandLine
    Exit
  }
}

# Create VHDX if it doesn't exist
if (-not (Test-Path "C:\DevDrive.vhdx")) {
    New-VHD -Path C:\DevDrive.vhdx -SizeBytes 1TB -Dynamic
}

# Mount, initialize, and format if not already done
if (-not (Get-DiskImage -ImagePath "C:\DevDrive.vhdx").Attached) {
    $vhd = Mount-VHD -Path C:\DevDrive.vhdx -PassThru | Get-Disk
    if ($vhd.PartitionStyle -eq "RAW") {
        Initialize-Disk -Number $vhd.Number -PartitionStyle GPT
        $part = New-Partition -DiskNumber $vhd.Number -UseMaximumSize -AssignDriveLetter
        Format-Volume -DriveLetter $part.DriveLetter -DevDrive -Confirm:$false
    }
}

# Reassign to D: if mounted on a different letter. Not while another volume
# holds D: (a second disk, an optical drive, a CI runner's work disk):
# Set-Partition only fails there, and the MountDevDrive task below moves that
# volume aside and mounts the Dev Drive at D: on the next boot.
$img = Get-DiskImage -ImagePath "C:\DevDrive.vhdx"
$letter = $null
if ($img.Attached) {
    $letter = ($img | Get-Disk | Get-Partition | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
    if ($letter -and $letter -ne 'D') {
        if (Get-Volume -DriveLetter D -ErrorAction SilentlyContinue) {
            Write-Host "notice: D: is taken by another volume; the Dev Drive is at ${letter}: until the MountDevDrive task moves it at the next boot"
        } else {
            Set-Partition -DriveLetter $letter -NewDriveLetter D
            $letter = 'D'
        }
    }
}

# Apply allowed filters
fsutil devdrv setfiltersallowed "PrjFlt, MsSecFlt, WdFilter, bindFlt, wcifs, FileInfo, ProcMon24"

# Label, only once the Dev Drive is the volume at D:
if ($letter -eq 'D' -and -not (Get-Volume -DriveLetter D).FileSystemLabel) {
    Set-Volume -DriveLetter D -NewFileSystemLabel "DevDrive"
}

# The MountDevDrive task: at every boot, as SYSTEM, compact the VHDX, then
# mount it at D:, moving any other volume that holds D: to the first free
# letter from E: on.
#
# Why compact here. The VHDX is dynamic and only grows: ReFS inside sends TRIM
# when files are deleted (fsutil behavior query DisableDeleteNotify), and the
# VHDX records those blocks as free, but its file on C: keeps their space
# until something compacts it. WSL gives such space back live by making its
# VHDXs sparse files and attaching them with sparse files allowed, through the
# Host Compute Service. No supported tool does that for a disk mounted on the
# host: Mount-VHD, diskpart and Disk Management all refuse a sparse VHDX
# ("Virtual hard disk files must be uncompressed and unencrypted and must not
# be sparse"), and getting past that would take an attach harness of our own,
# around virtdisk flags Microsoft documents by name only. Optimize-VHD is
# Microsoft's own, supported compaction, but it needs the VHDX detached (or
# attached read-only), and the Dev Drive is attached read-write from boot to
# shutdown. Boot, before this task mounts it, is the one time it is not. So
# space freed on D: comes back at the next boot rather than live: most of the
# benefit, through Microsoft-tested paths only.
#
# Pretrimmed is the mode for a detached VHDX: it reclaims the blocks the VHDX
# already knows are free from those TRIMs (Quick turns into it anyway when the
# disk is not attached read-only). Full would read the whole file at every boot
# hunting for zeroed blocks, and the free-space query it adds only understands
# NTFS, not the ReFS inside.
#
# The cost is boot time: D: appears once the compaction finishes, so the first
# boot after a lot was deleted takes longer to mount it. A failed compaction
# never keeps D: from mounting. Each boot's result goes to
# C:\DevDrive.optimize.log, one line, replaced every boot.
#
# Already attached (the task run by hand mid-session) means there is nothing to
# compact and nothing to mount; the task leaves it as it is, rather than moving
# the Dev Drive itself off D: as "the volume holding D:".
$BootScript = @'
$Vhd = 'C:\DevDrive.vhdx'
$Log = 'C:\DevDrive.optimize.log'
if ((Get-DiskImage -ImagePath $Vhd).Attached) { exit 0 }

$Before = (Get-Item -LiteralPath $Vhd).Length
$Started = Get-Date
try {
    Optimize-VHD -Path $Vhd -Mode Pretrimmed -ErrorAction Stop
    $After = (Get-Item -LiteralPath $Vhd).Length
    $Line = '{0:s} Optimize-VHD -Mode Pretrimmed: {1:N2} GiB -> {2:N2} GiB in {3:N0} s' -f $Started, ($Before / 1GB), ($After / 1GB), ((Get-Date) - $Started).TotalSeconds
}
catch {
    $Line = '{0:s} Optimize-VHD failed, mounting anyway: {1}' -f $Started, $_
}
Set-Content -LiteralPath $Log -Value $Line

$Free = 69..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Get-Volume -DriveLetter $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1
$Taken = Get-CimInstance Win32_Volume -Filter "DriveLetter='D:'"
if ($Taken) { Set-CimInstance -InputObject $Taken -Property @{ DriveLetter = "${Free}:" } }
$Partition = Mount-VHD -Path $Vhd -PassThru | Get-Disk | Get-Partition | Where-Object { $_.Type -ne 'Reserved' }
if ($Partition.DriveLetter -ne 'D') { $Partition | Set-Partition -NewDriveLetter D }
'@

# Encoded rather than inline -Command, so the script needs no escaping and the
# task carries it whole; a file beside it would be one more thing SYSTEM runs
# that has to be kept unwritable by users.
#
# Registered with -Force, replacing a task from an earlier version of this
# script: run_once_ re-runs it whenever this file changes, so the task always
# matches what is above.
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($BootScript))
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $Encoded"
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "MountDevDrive" -Action $action -Trigger $trigger `
    -RunLevel Highest -User "SYSTEM" -Force | Out-Null
