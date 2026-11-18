{{- /* The body of 00-{linux,macos}/155-syncthing, after their preambles.
       Applies .chezmoidata/syncthing.toml (docs/syncthing.md) to this node's
       running Syncthing: the REST half is .chezmoitemplates/syncthing-apply.py,
       which 00-nt/155-syncthing mirrors in PowerShell. */ -}}
# run_after_, every apply, so a node whose Syncthing was not running yet, or
# whose configuration was changed in the GUI, is set up again next time.
# Masked under useDummySecrets in .chezmoiignore.tmpl: the hub's ID is
# age-encrypted, and decrypted here at run time.

# The permissions Syncthing carries to the other nodes, set here on what
# exists. A folder Syncthing has yet to create gets its mode on the next apply.
{{- range .syncthing.folders }}
{{-   $dir := index .path $.chezmoi.os | replace "~/" "$HOME/" }}
{{-   with get . "mode" }}
if [ -d "{{ $dir }}" ]; then
	chmod {{ . }} "{{ $dir }}"
fi
{{-   end }}
{{-   range $name, $mode := (get . "files" | default dict) }}
if [ -f "{{ $dir }}/{{ $name }}" ]; then
	chmod {{ $mode }} "{{ $dir }}/{{ $name }}"
fi
{{-   end }}
{{- end }}

# Syncthing runs on native Linux and on macOS only: 150-user-services starts
# it on neither WSL nor a container.
if [ "${IS_WSL:-0}" -eq 1 ] || [ "${CONTAINERIZED:-0}" -eq 1 ]; then
	echo "debug: no Syncthing runs here (WSL or a container); skipping" >&2
	exit 0
fi

# PATH's syncthing (the distro package, or brew's formula), else the
# syncthing-app cask's own copy.
syncthing=""
if command -v syncthing >/dev/null 2>&1; then
	syncthing="$(command -v syncthing)"
elif [ -x /Applications/Syncthing.app/Contents/Resources/syncthing/syncthing ]; then
	syncthing=/Applications/Syncthing.app/Contents/Resources/syncthing/syncthing
fi
if [ -z "$syncthing" ]; then
	echo "debug: Syncthing is not installed; skipping" >&2
	exit 0
fi

# The CLI finds Syncthing's configuration on its own and asks the running
# instance, so failing here means Syncthing is not running. Its syntax is the
# same in 1.29 (Ubuntu's) and 2.x.
if ! api_key="$("$syncthing" cli config gui apikey get 2>/dev/null)" || [ -z "$api_key" ]; then
	echo "notice: Syncthing isn't running, so its configuration waits for an apply while it is" >&2
	exit 0
fi
address="$("$syncthing" cli config gui raw-address get)"
scheme=http
if [ "$("$syncthing" cli config gui raw-use-tls get)" = true ]; then
	scheme=https
fi
case "$address" in
	unix://* | /*)
		echo "warning: Syncthing's GUI listens on a Unix socket ($address); its configuration is left as it is" >&2
		exit 0
		;;
	0.0.0.0:*) address="127.0.0.1:${address#0.0.0.0:}" ;;
	'[::]:'*) address="[::1]:${address#'[::]:'}" ;;
	:*) address="127.0.0.1$address" ;;
esac

{{- if .useDummySecrets }}
# Dummy secrets: of those hosts only the hub itself gets here
# (.chezmoiignore.tmpl), and it needs no ID. An empty one tells the REST half
# it is the hub.
hub_id=""
{{- else }}
# (read -d '' returns 1 at the heredoc's end, having no NUL to stop at.)
IFS= read -r -d '' hub_id_ciphertext <<'CHEZMOI_AGE_PAYLOAD' || true
{{ include (joinPath .chezmoi.sourceDir ".chezmoitemplates" "secrets" .syncthing.hub.idCiphertext) | trim }}
CHEZMOI_AGE_PAYLOAD
if ! hub_id="$(printf '%s' "$hub_id_ciphertext" | '{{ .chezmoi.executable | replace "'" "'\\''" }}' --config '{{ .chezmoi.configFile | replace "'" "'\\''" }}' decrypt)"; then
	echo "error: failed to decrypt the hub's device ID ({{ .syncthing.hub.idCiphertext }})" >&2
	exit 1
fi
hub_id="$(printf '%s' "$hub_id" | tr -d '[:space:]')"
{{- end }}

IFS= read -r -d '' desired <<'CHEZMOI_SYNCTHING_JSON' || true
{{ template "syncthing-desired.json" . }}
CHEZMOI_SYNCTHING_JSON

IFS= read -r -d '' apply_py <<'CHEZMOI_SYNCTHING_PY' || true
{{ include (joinPath .chezmoi.sourceDir ".chezmoitemplates" "syncthing-apply.py") }}
CHEZMOI_SYNCTHING_PY
ST_APIKEY="$api_key" python3 -c "$apply_py" "$scheme://$address" "$hub_id" "$desired"
