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
        Set-Partition -DriveLetter $part.DriveLetter -NewDriveLetter D
    }
}

# Reassign to D: if mounted on a different letter
$img = Get-DiskImage -ImagePath "C:\DevDrive.vhdx"
if ($img.Attached) {
    $letter = ($img | Get-Disk | Get-Partition | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
    if ($letter -and $letter -ne 'D') {
        Set-Partition -DriveLetter $letter -NewDriveLetter D
    }
}

# Apply allowed filters
fsutil devdrv setfiltersallowed "PrjFlt, MsSecFlt, WdFilter, bindFlt, wcifs, FileInfo, ProcMon24"

# Label
if (-not (Get-Volume -DriveLetter D).FileSystemLabel) {
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
