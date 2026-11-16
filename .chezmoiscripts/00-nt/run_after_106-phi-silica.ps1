# Removes Phi Silica, the on-device language model Windows Update installs on
# Copilot+ PCs, and removes it again whenever Windows Update brings it back.
# On a Copilot+ PC, one with an NPU, Settings > System > AI components lists
# "AI Phi Silica" with no Uninstall button: Windows Update records the NPU
# model as not removable. What comes off is the model and every copy of it
# compiled for the NPU. The ROG Flow Z13 had 19.1 GB of those, eight builds
# for AMD's NPU, one per runtime and NPU driver version it had been through,
# only the newest of them in use. The Windows AI policies in
# registry-system.reg keep apps and Click to Do off whatever copy is there.
#
# How: the Uninstall button runs `SystemSettingsAdminFlows.exe
# AIComponentsAdminFlow <product>` elevated, which calls RemoveAsync on
# Windows.AI.Management.Internal.AIComponentManager (AIComponentMgmt.dll).
# That removes the update product ms-uup://Product/<product> -- its packages,
# and their machine data folder under
# %ProgramData%\Microsoft\Windows\AppRepository\Families -- for LOCAL SERVICE
# (S-1-5-19), the account every WindowsWorkload package is registered to, and
# the product's key below $Installed goes with them. RemoveAsync refuses with
# E_ACCESSDENIED (0x80070005) unless that key's IsRemovable reads "true", and
# Windows Update writes "False" there for the NPU model. Administrators can
# write it, so the elevated half sets it to "True" first and puts the old value
# back if the removal fails. Found by decompiling both binaries on build
# 26300.9974 (26H2), and done by hand that way on 2026-11-15. Every piece of it
# is internal and undocumented, so any update can change it.
#
# run_after_, not a run_onchange_ keyed on the build as
# 99-nt-*/010-hibernate-not-s0ix is: Windows Update can bring the product back
# with any AI component update, and those come on their own schedule and leave
# `ver` as it was. The check is one registry read, unelevated: the product's key
# below $Installed exists exactly while the product is installed. With nothing
# to remove there is no UAC prompt, and a machine without an NPU (GitHub's
# runners) never has the key.
#
# Matched by pattern, because the product's name carries the silicon:
# Windows.Workload.PhiSilica.STX.amd64 is AMD Strix's. Aion Instruct, which
# Microsoft says replaces Phi Silica on retail machines in January 2027, will
# be a product of its own; its pattern goes in $Products once its name is
# known.
#
# 106: beside 105-retired-packages, and after 000-registry, which puts sudo in
# inline mode, where it waits for the elevated half and returns its exit code.

$Installed = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\PersistentDynamicInstalled'
$Products = @('Windows.Workload.PhiSilica.*')
$AdminFlows = Join-Path $env:SystemRoot 'System32\SystemSettingsAdminFlows.exe'

# The names of the matching products installed now.
function Get-Present {
    foreach ($Key in @(Get-ChildItem -LiteralPath $Installed -ErrorAction SilentlyContinue)) {
        foreach ($Pattern in $Products) {
            if ($Key.PSChildName -like $Pattern) { $Key.PSChildName; break }
        }
    }
}

# A string as a single-quoted PowerShell literal.
function Format-Literal {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

$Present = @(Get-Present)
if ($Present.Count -eq 0) {
    Write-Host 'debug: Phi Silica is not installed'
    exit 0
}
foreach ($Id in $Present) {
    $Version = (Get-ItemProperty -LiteralPath (Join-Path $Installed $Id) -ErrorAction SilentlyContinue).Version
    Write-Host "notice: removing $Id $Version, which Windows Update installed with no Uninstall in Settings"
}

# The elevated half: one script handed to sudo as -EncodedCommand, so one UAC
# prompt for every product, exiting with how many failed. Its effect is read
# back unelevated below. Where its output is redirected, Windows PowerShell
# writes progress (the "Preparing modules for first use" of the cmdlets'
# module autoload) and Write-Host records to stderr as CLIXML; progress is
# off and -OutputFormat Text below keeps both plain.
$Body = @'
$ProgressPreference = 'SilentlyContinue'
$Failed = 0
foreach ($Id in $Ids) {
    $Key = Join-Path $Installed $Id
    if (-not (Test-Path -LiteralPath $Key)) { continue }
    $Was = (Get-ItemProperty -LiteralPath $Key).IsRemovable
    Set-ItemProperty -LiteralPath $Key -Name IsRemovable -Value 'True' -Type String
    $Flow = Start-Process -FilePath $AdminFlows -ArgumentList 'AIComponentsAdminFlow', $Id -Wait -PassThru
    if ($Flow.ExitCode -ne 0) {
        Write-Host ('error: SystemSettingsAdminFlows.exe AIComponentsAdminFlow {0} exited 0x{1:X8}' -f $Id, $Flow.ExitCode)
        if (($null -ne $Was) -and (Test-Path -LiteralPath $Key)) {
            Set-ItemProperty -LiteralPath $Key -Name IsRemovable -Value $Was -Type String
        }
        $Failed++
    }
}
exit $Failed
'@
$Elevated = @(
    "`$Installed = $(Format-Literal $Installed)"
    "`$AdminFlows = $(Format-Literal $AdminFlows)"
    "`$Ids = @($(($Present | ForEach-Object { Format-Literal $_ }) -join ', '))"
    $Body
) -join "`r`n"
$Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Elevated))

& sudo powershell -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $Encoded
$Code = $LASTEXITCODE

$Left = @(Get-Present)
if ($Left.Count -gt 0) {
    Write-Host "error: still installed: $($Left -join ', ') (sudo exited $Code) -- was the elevation prompt declined?"
    exit 1
}
if ($Code -ne 0) {
    Write-Host "error: every product is gone, but $Code removal(s) reported failure; see above"
    exit 1
}
Write-Host "notice: removed $($Present -join ', ')"
