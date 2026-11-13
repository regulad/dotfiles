# Grows the NTFS change (USN) journal on every fixed, lettered NTFS volume
# that has one, to 1 GiB with a 128 MiB allocation delta.
#
# The journal is a ring of records -- one or more per create, write, rename,
# delete or close of any file -- and whatever follows it (the Search indexer,
# sync, backup and file-search tools) only has to read what changed since its
# last position. Once that position has been trimmed off the front it has
# nothing to go on and rescans the whole volume. Windows creates the journal
# at 32 MiB with an 8 MiB delta. A record is roughly 100 bytes, so that is a
# few hundred thousand records: one Windows update, scoop update or package
# install can turn it over. On the machine this was written for, C: had
# logged 66.6 GiB of records in 581 days, 117 MiB a day averaged over days
# the machine was off as well, so 32 MiB held about six and a half hours of
# history. 1 GiB holds over a week at that average and absorbs bursts. The
# journal takes at most m + a of disk, 1.125 GiB here, and costs no extra I/O:
# the same records are written whatever the size, and only trimming happens
# less often. The one real cost is that the names of deleted files stay
# readable to an administrator for that much longer.
#
# `fsutil usn createjournal` on a volume that already has a journal changes
# only its maximum size and allocation delta. The journal keeps its ID and its
# records, so nothing following it rescans because of this.
#
# Grow-only, and only journals that exist. A journal larger than the target
# (someone tuned it) is left alone. A volume with no journal has nothing
# following it, so none is created; once something creates one at the default
# size, the next apply grows it. And never more than 1/128 of a volume, so a
# small one gets proportionally less (512 MiB on 64 GiB). NTFS only: the ReFS
# Dev Drive from 050-dev-drive churns far less (19 MiB of records in four days
# against its 70 MiB journal) and lives in a dynamic VHDX, which would grow on
# C: to hold a bigger journal.
#
# run_after_, because the check costs nothing and needs no elevation, while
# deleting the journal, reformatting or resetting Windows puts the default
# back. Same shape as 040-telnet-client: read unelevated, sudo only for what
# is off -- one UAC prompt for all volumes, as an -EncodedCommand as in
# 99-nt-*/010-hibernate-not-s0ix -- then read back. sudo is inline
# (registry-system.reg sets it), so it waits and returns the exit code.
#
# The journal is read with FSCTL_QUERY_USN_JOURNAL rather than by parsing
# `fsutil usn queryjournal`, whose labels are localized. An unelevated user
# cannot open the volume itself (\\.\C:) for reading, but a handle to its root
# directory with no access rights asked for answers the same ioctl.

$TargetMax = 1GB
$TargetDelta = 128MB
$VolumeShare = 128

Add-Type -Namespace Dotfiles -Name UsnJournal -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool DeviceIoControl(Microsoft.Win32.SafeHandles.SafeFileHandle device, uint code, IntPtr inBuffer, uint inSize, byte[] outBuffer, uint outSize, out uint returned, IntPtr overlapped);
'@

# The journal on a volume, by drive letter: its ID, maximum size and
# allocation delta, the UInt64s at offsets 0, 40 and 48 of USN_JOURNAL_DATA,
# which every version of the struct shares. $null when the volume has no
# journal (ERROR_JOURNAL_NOT_ACTIVE); a string when the query fails for any
# other reason.
function Get-UsnJournal {
    param([string]$Letter)
    # FILE_SHARE_READ|WRITE|DELETE, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS
    # (which a handle to a directory needs), no access rights.
    $Handle = [Dotfiles.UsnJournal]::CreateFileW("${Letter}:\", 0, 7, [IntPtr]::Zero, 3, 0x02000000, [IntPtr]::Zero)
    if ($Handle.IsInvalid) {
        return "cannot open ${Letter}:\ (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
    try {
        $Buffer = [byte[]]::new(80)
        $Returned = [uint32]0
        # FSCTL_QUERY_USN_JOURNAL
        if (-not [Dotfiles.UsnJournal]::DeviceIoControl($Handle, 0x000900F4, [IntPtr]::Zero, 0, $Buffer, 80, [ref]$Returned, [IntPtr]::Zero)) {
            $Err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($Err -eq 1179) { return $null }
            return "cannot query the journal on ${Letter}: (Win32 error $Err)"
        }
    }
    finally {
        $Handle.Dispose()
    }
    return [pscustomobject]@{
        Id    = [BitConverter]::ToUInt64($Buffer, 0)
        Max   = [BitConverter]::ToUInt64($Buffer, 40)
        Delta = [BitConverter]::ToUInt64($Buffer, 48)
    }
}

function Format-MiB {
    param([double]$Bytes)
    return '{0:N0} MiB' -f ($Bytes / 1MB)
}

$Volumes = @(Get-Volume | Where-Object {
        ([string]$_.DriveLetter -match '^[A-Za-z]$') -and ($_.FileSystem -eq 'NTFS') -and ("$($_.DriveType)" -eq 'Fixed')
    } | Sort-Object DriveLetter)

$Plans = @(foreach ($Volume in $Volumes) {
        $Letter = ([string]$Volume.DriveLetter).ToUpperInvariant()
        $Journal = Get-UsnJournal $Letter
        if ($null -eq $Journal) {
            Write-Host "debug: ${Letter}: has no USN journal; nothing to grow"
            continue
        }
        if ($Journal -is [string]) {
            Write-Host "warning: $Journal; leaving it as it is"
            continue
        }
        # Whole MiB, at most 1/128 of the volume, the delta in proportion.
        $Max = [Math]::Min([double]$TargetMax, [Math]::Floor($Volume.Size / $VolumeShare / 1MB) * 1MB)
        $Delta = [Math]::Floor($Max * ($TargetDelta / $TargetMax) / 1MB) * 1MB
        if ($Journal.Max -ge $Max) {
            Write-Host "debug: USN journal on ${Letter}: already $(Format-MiB $Journal.Max) (target $(Format-MiB $Max))"
            continue
        }
        [pscustomobject]@{ Letter = $Letter; Before = $Journal; Max = [uint64]$Max; Delta = [uint64]$Delta }
    })

if ($Plans.Count -eq 0) {
    exit 0
}

foreach ($Plan in $Plans) {
    Write-Host "debug: growing the USN journal on $($Plan.Letter): from $(Format-MiB $Plan.Before.Max) to $(Format-MiB $Plan.Max), allocation delta $(Format-MiB $Plan.Before.Delta) -> $(Format-MiB $Plan.Delta)"
}

# Every createjournal runs even if one fails, so the read-back sees them all;
# the elevated script exits with how many failed.
$Elevated = @(
    '$Failed = 0'
    foreach ($Plan in $Plans) {
        "& fsutil.exe usn createjournal m=$($Plan.Max) a=$($Plan.Delta) $($Plan.Letter):"
        "if (`$LASTEXITCODE) { `$Failed++; Write-Host ('error: fsutil usn createjournal on $($Plan.Letter): exited ' + `$LASTEXITCODE) }"
    }
    'exit $Failed'
) -join "`r`n"
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Elevated))

& sudo powershell -NoProfile -NonInteractive -EncodedCommand $Encoded
$Code = $LASTEXITCODE

$Short = 0
foreach ($Plan in $Plans) {
    $After = Get-UsnJournal $Plan.Letter
    if (($null -eq $After) -or ($After -is [string]) -or ($After.Max -lt $Plan.Max)) {
        $Now = if ($null -eq $After) { 'no journal' } elseif ($After -is [string]) { $After } else { Format-MiB $After.Max }
        Write-Host "error: USN journal on $($Plan.Letter): is $Now, not $(Format-MiB $Plan.Max) (sudo exited $Code) -- was the elevation prompt declined?"
        $Short++
        continue
    }
    Write-Host "notice: USN journal on $($Plan.Letter): grown to $(Format-MiB $After.Max), allocation delta $(Format-MiB $After.Delta)"
    if ($After.Id -ne $Plan.Before.Id) {
        Write-Host "warning: the journal on $($Plan.Letter): was recreated rather than resized (ID 0x$('{0:X16}' -f $Plan.Before.Id) -> 0x$('{0:X16}' -f $After.Id)); whatever follows it will rescan the volume once"
    }
}
if ($Short -gt 0) {
    exit 1
}
if ($Code -ne 0) {
    Write-Host "error: every journal reads back as wanted, but $Code createjournal call(s) failed; see above"
    exit 1
}
