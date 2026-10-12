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

# Register scheduled task if not already present
if (-not (Get-ScheduledTask -TaskName "MountDevDrive" -ErrorAction SilentlyContinue)) {
    # moves any drive on D to E or greater and puts the dev drive there instead
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NonInteractive -WindowStyle Hidden -Command `"`$free=(69..90|%{[char]`$_}|?{-not(Get-Volume -DriveLetter `$_ -ErrorAction SilentlyContinue)}|select -First 1);`$v=Get-CimInstance Win32_Volume -Filter 'DriveLetter=''D:''';if(`$v){Set-CimInstance -InputObject `$v -Property @{DriveLetter=(`$free+':')}};`$p=Mount-VHD -Path C:\DevDrive.vhdx -PassThru|Get-Disk|Get-Partition|?{`$_.Type -ne 'Reserved'};if(`$p.DriveLetter -ne 'D'){`$p|Set-Partition -NewDriveLetter D}`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName "MountDevDrive" -Action $action -Trigger $trigger `
        -RunLevel Highest -User "SYSTEM"
}
