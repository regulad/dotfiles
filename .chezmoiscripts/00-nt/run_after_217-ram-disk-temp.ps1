# Points this account's TEMP and TMP at E:\Temp, the folder MountRamDisk
# (216-ram-disk) makes on the RAM disk at every boot, private to the account
# that applied 216. Only once that folder is there and takes a file: a TEMP
# pointing at a folder that does not exist breaks whatever starts next. Should
# the folder be gone, a TEMP and TMP still pointing into E:\Temp are put back
# on the Windows default, %USERPROFILE%\AppData\Local\Temp; values pointing
# anywhere else are left alone.
#
# E:\Temp rather than E:\ itself: a drive root as TEMP is untested here, and
# the root holds System Volume Information, which anything sweeping TEMP would
# trip over.
#
# Here and not in registry-user.reg, with the other per-user values: 001
# imports that before 216 has made the folder, on a first apply before the RAM
# disk exists at all, and a static value cannot check either. Gated like 216,
# native x64 Windows only (.chezmoiignore.tmpl).
#
# run_after_, since the check costs nothing and needs no elevation, so the
# values follow the folder on every apply. A new value is announced the way
# 001-user-registry announces its own, with the WM_SETTINGCHANGE "Environment"
# broadcast: programs started afterwards get it, programs already running keep
# what they had. WSL keeps its swap and crash dumps in AppData\Local\Temp
# whatever TEMP says; it looks that folder up itself.

$Wanted = 'E:\Temp'
$Default = '%USERPROFILE%\AppData\Local\Temp'

$Usable = $false
if (Test-Path -LiteralPath $Wanted -PathType Container) {
    $Probe = Join-Path $Wanted (".chezmoi-probe-{0}" -f [guid]::NewGuid())
    try {
        [IO.File]::WriteAllText($Probe, '')
        [IO.File]::Delete($Probe)
        $Usable = $true
    } catch {
        Write-Host "warning: $Wanted is there but cannot be written to: $($_.Exception.Message)"
    }
}

$Key = Get-Item -LiteralPath 'HKCU:\Environment'
$Changes = @()
foreach ($Name in 'TEMP', 'TMP') {
    $Now = $Key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    if ($Usable) { $Target = $Wanted }
    elseif ("$Now" -like 'E:\Temp*') { $Target = $Default }
    else { continue }
    if ($Now -ne $Target) {
        Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name $Name -Value $Target -Type ExpandString
        $Changes += "$Name '$Now' -> '$Target'"
    }
}

if ($Changes.Count -gt 0) {
    Add-Type -Namespace Dotfiles -Name EnvBroadcast -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
    $Result = [UIntPtr]::Zero
    [void][Dotfiles.EnvBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$Result)
    foreach ($Change in $Changes) { Write-Host "notice: $Change; programs started from now on use it" }
} elseif ($Usable) {
    Write-Host "debug: TEMP and TMP already point at $Wanted"
}

if (-not $Usable) {
    Write-Host "warning: $Wanted is not there, so TEMP and TMP are not on the RAM disk; C:\RamDisk.log says: $(Get-Content -LiteralPath 'C:\RamDisk.log' -ErrorAction SilentlyContinue)"
}
