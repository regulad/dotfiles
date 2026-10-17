# Ciphertext is embedded so rotations change the rendered hook's hash.
'{{ .root.chezmoi.executable | replace "'" "'\\''" }}' --config '{{ .root.chezmoi.configFile | replace "'" "'\\''" }}' decrypt --output "$private_import_dir/{{ .name | trimSuffix ".age" }}" <<'CHEZMOI_AGE_PAYLOAD'
{{ include (joinPath .root.chezmoi.sourceDir ".chezmoitemplates" "secrets" .name) | trim }}
CHEZMOI_AGE_PAYLOAD
