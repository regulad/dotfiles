# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
  if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
    $CommandLine = "-NoExit -File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
    Start-Process -Wait -FilePath powershell.exe -Verb Runas -ArgumentList $CommandLine
    Exit
  }
}

# MicrosoftCorporationII.WindowsSubsystemForAndroid_2407.40000.4.0_neutral_._8wekyb3d8bbwe.msixbundle
if (-not (Get-AppxPackage -Name "MicrosoftCorporationII.WindowsSubsystemForAndroid" | Where-Object { $_.Version -eq "2407.40000.4.0" })) {
    $tmp = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_.FullName }
    try {
        $resp = Invoke-WebRequest -Uri "https://nextcloud.regulad.xyz/public.php/dav/files/MeQrxoZ9JGgoaRK"
        $filename = [System.Net.Http.Headers.ContentDispositionHeaderValue]::Parse(
            $resp.Headers['Content-Disposition']
        ).FileName.Trim('"')
        $out = Join-Path $tmp.FullName $filename
        [System.IO.File]::WriteAllBytes($out, $resp.Content)
        Add-AppxPackage -Path $out
    } finally {
        Remove-Item -Recurse -Force $tmp.FullName
    }
}
