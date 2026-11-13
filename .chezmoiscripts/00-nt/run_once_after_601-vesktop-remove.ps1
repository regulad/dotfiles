# Takes Vesktop off a machine that still has it. 100-winget installs Discord
# itself in its place, with Vencord injected by 600-vencord: Vesktop cannot
# receive rich presence. Dropping a package from a list never uninstalls it.
# Vesktop's data, ~/.config/vesktop behind the %APPDATA%\vesktop link, stays.
#
# run_once_: chezmoi records the script only after a clean exit, so a failed
# uninstall is tried again on the next apply. Same shape as
# 207-scoop-npiperelay-remove.
function Test-Vesktop {
    & winget list --id Vencord.Vesktop --exact --accept-source-agreements --disable-interactivity *> $null
    return $LASTEXITCODE -eq 0
}

if (-not (Test-Vesktop)) {
    Write-Host 'debug: Vesktop is not installed'
    exit 0
}

# Its uninstaller cannot remove files the running app holds.
$Running = @(Get-Process -Name Vesktop -ErrorAction SilentlyContinue)
if ($Running.Count) {
    Write-Host 'notice: closing Vesktop to uninstall it'
    $Running | Stop-Process -Force -ErrorAction SilentlyContinue
    $Running | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
}

Write-Host 'notice: uninstalling Vesktop; Discord with Vencord injected replaces it (600-vencord)'
& winget uninstall --id Vencord.Vesktop --exact --silent --accept-source-agreements --disable-interactivity
# Its NSIS uninstaller hands off to a copy of itself in %TEMP% and returns at
# once, and winget with it, so the result is polled for.
$Deadline = (Get-Date).AddSeconds(120)
while ((Test-Vesktop) -and (Get-Date) -lt $Deadline) { Start-Sleep -Seconds 2 }
if (Test-Vesktop) {
    Write-Host 'error: winget uninstall Vencord.Vesktop did not remove it'
    exit 1
}
Write-Host 'notice: Vesktop uninstalled'
