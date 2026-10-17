@'
{{ include (joinPath .root.chezmoi.sourceDir ".chezmoitemplates" "secrets" .name) | trim }}
'@ | & '{{ .root.chezmoi.executable | replace "'" "''" }}' --config '{{ .root.chezmoi.configFile | replace "'" "''" }}' decrypt --output (Join-Path $ImportDir '{{ .name | trimSuffix ".age" }}')
if ($LASTEXITCODE -ne 0) { throw 'error: failed to decrypt {{ .name }}' }
