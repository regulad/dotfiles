{{- if .useDummySecrets }}
echo "debug: useDummySecrets is set, skipping GPG key import" >&2
{{- else }}
if ! command -v gpg &>/dev/null; then
    echo "error: gpg not available, can't import GPG keys" >&2
    exit 1
fi
{{ template "private-import-temp.sh" . }}
{{ template "decrypt-import.sh" (dict "root" . "name" "gpg-public.asc.age") }}
{{ template "decrypt-import.sh" (dict "root" . "name" "gpg-secret.asc.age") }}
gpg --batch --list-keys >/dev/null 2>&1
gpg --batch --yes --import "$private_import_dir/gpg-public.asc"
# Loopback unlocks the incoming key without an interactive pinentry dialog.
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
    --import "$private_import_dir/gpg-secret.asc" <<'GPG_IMPORT_PASSPHRASE'
{{ (bitwarden "item" "f61fd2e0-3284-4c3b-8274-87cdeec73aa2").login.password }}
GPG_IMPORT_PASSPHRASE
{{- end }}
