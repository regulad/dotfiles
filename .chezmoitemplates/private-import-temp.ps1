# Restrict the temporary import directory before writing secrets.
$ImportDir = Join-Path ([IO.Path]::GetTempPath()) ('chezmoi-import-' + [guid]::NewGuid())
$ImportAcl = New-Object System.Security.AccessControl.DirectorySecurity
$ImportSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$ImportAcl.SetOwner($ImportSid)
$ImportAcl.SetAccessRuleProtection($true, $false)
$ImportRule = New-Object System.Security.AccessControl.FileSystemAccessRule($ImportSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$ImportAcl.AddAccessRule($ImportRule)
# Create with the ACL in place, on both Windows PowerShell 5.1 and PowerShell 7.
if ($PSVersionTable.PSEdition -eq 'Core') {
    [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($ImportDir), $ImportAcl)
} else {
    [IO.Directory]::CreateDirectory($ImportDir, $ImportAcl) | Out-Null
}
