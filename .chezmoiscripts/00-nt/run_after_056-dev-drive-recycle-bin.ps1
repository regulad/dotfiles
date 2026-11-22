# Turns the Recycle Bin off for the Dev Drive from 050-dev-drive, as Recycle
# Bin Properties' "Don't move files to the Recycle Bin. Remove files
# immediately when deleted." does for one drive: whatever deletes through the
# shell there -- Explorer, an editor's "move to trash", anything using
# SHFileOperation or IFileOperation with undo -- removes the file at once.
# Every other volume keeps its Recycle Bin.
#
# A recycled file is only moved, into D:\$RECYCLE.BIN, so it keeps its space
# on D: and in the dynamic VHDX on C: until the bin is emptied, and only the
# next boot's compaction (050's MountDevDrive task) gives that back to C:. A
# deleted tree of repositories or package data is also hundreds of thousands
# of files, each moved and recorded on its own.
#
# The setting is per user and per volume: NukeOnDelete under
# HKCU\...\Explorer\BitBucket\Volume\{volume GUID}, the key Explorer keeps for
# each volume it has seen. The volume is found through the disk its VHDX
# backs, not by its letter, so where another volume holds D: (050) nothing
# else is touched. The GUID is the mount manager's, which every remount of the
# same VHDX keeps; a recreated VHDX is a new volume, which the next apply sets.
#
# run_after_, every apply: it reads one value, and writes only when it is
# off. No elevation: the key is the user's own.

$Vhd = 'C:\DevDrive.vhdx'
$BitBucket = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume'

$Disk = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.Location -eq $Vhd }) | Select-Object -First 1
if (-not $Disk) {
    Write-Host "debug: $Vhd is not attached (050-dev-drive); no Dev Drive Recycle Bin to turn off"
    exit 0
}

$Volumes = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue |
        Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { "$($_.UniqueId)" -match '\{[0-9A-Fa-f-]{36}\}' })
if ($Volumes.Count -eq 0) {
    Write-Host "warning: $Vhd is attached as disk $($Disk.Number) but has no volume; its Recycle Bin is left as it is"
    exit 0
}

$Failed = 0
foreach ($Volume in $Volumes) {
    $Guid = [regex]::Match("$($Volume.UniqueId)", '\{[0-9A-Fa-f-]{36}\}').Value.ToLowerInvariant()
    $Name = if ($Volume.DriveLetter) { "$($Volume.DriveLetter):" } else { $Guid }
    $Key = Join-Path $BitBucket $Guid
    $Current = (Get-ItemProperty -LiteralPath $Key -Name NukeOnDelete -ErrorAction SilentlyContinue).NukeOnDelete
    if ($Current -eq 1) {
        Write-Host "debug: the Recycle Bin on the Dev Drive ($Name) is already off"
        continue
    }
    # Never New-Item -Force on a key that exists: on the registry it replaces
    # the key, dropping MaxCapacity and anything else Explorer keeps there.
    if (-not (Test-Path -LiteralPath $Key)) {
        New-Item -Path $Key -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $Key -Name NukeOnDelete -Value 1 -Type DWord
    if ((Get-ItemProperty -LiteralPath $Key -Name NukeOnDelete -ErrorAction SilentlyContinue).NukeOnDelete -eq 1) {
        Write-Host "notice: turned the Recycle Bin off on the Dev Drive ($Name): files deleted there are removed at once"
    }
    else {
        Write-Host "error: NukeOnDelete under $Key does not read back as 1"
        $Failed++
    }
}

if ($Failed) {
    exit 1
}
