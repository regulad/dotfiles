# .chezmoidata/apt-sources.toml's repositories, for 00-linux/021-apt-packages:
# enable_apt_source <name> writes one, before the `apt update` that reads it.
# Needs sudo; call it after require_sudo. An optional source with nothing
# published for this host's suite goes into APT_UNPUBLISHED_SOURCES
# (" <name> <name> ") instead, and its packages are to be left out.

APT_UNPUBLISHED_SOURCES=" "
enable_apt_source() {
	case "$1" in
{{- range $name, $src := .aptSources }}
	{{ $name }})
		write_apt_source {{ $name | quote }} {{ join " " $src.components | quote }} {{ if get $src "optional" }}optional{{ else }}required{{ end }} <<'CHEZMOI_APT_SOURCE_CHANNELS'
{{ range $src.channels }}{{ .suite }} {{ .uri }} {{ .key }}
{{ end -}}
CHEZMOI_APT_SOURCE_CHANNELS
		;;
{{- end }}
	*)
		echo "error: $1 is not a source in .chezmoidata/apt-sources.toml" >&2
		return 1
		;;
	esac
}

# The key a channel names, from .chezmoitemplates/keys/.
apt_source_key() {
	case "$1" in
{{- $keys := list }}
{{- range $name, $src := .aptSources }}
{{-   range $src.channels }}
{{-     if not (has .key $keys) }}
{{-       $keys = append $keys .key }}
	{{ .key | quote }})
		cat <<'CHEZMOI_APT_SOURCE_KEY'
{{ include (joinPath $.chezmoi.sourceDir ".chezmoitemplates" "keys" .key) | trim }}
CHEZMOI_APT_SOURCE_KEY
		;;
{{-     end }}
{{-   end }}
{{- end }}
	*)
		echo "error: no key $1 in .chezmoitemplates/keys" >&2
		return 1
		;;
	esac
}

# One source: $1 its name, $2 its components, $3 "optional" or "required", and
# its channels on stdin, one "<suite> <uri> <key>" per line. Writes
# /etc/apt/sources.list.d/<name>.sources with a stanza for each channel of
# this host's suite (VERSION_CODENAME, from the /etc/os-release the preamble
# reads) whose InRelease exists, and installs the keys those name to
# /etc/apt/keyrings. A channel that answers 404 has published nothing for the
# suite yet and is left out; any other answer, or none, is an error, and
# changes nothing. So is a suite with no channel that has published anything,
# unless the source is optional: then it goes into APT_UNPUBLISHED_SOURCES, and
# a .sources file an earlier release had for it is removed.
write_apt_source() {
	local name=$1 components=$2 optional=$3
	local list_file="/etc/apt/sources.list.d/$name.sources"
	local suite uri key status wanted="" keys="" key_file
	while read -r suite uri key; do
		[ -n "$suite" ] || continue
		[ "$suite" = "${VERSION_CODENAME:-}" ] || continue
		status=$(curl -sSL -o /dev/null -w '%{http_code}' "$uri/dists/$suite/InRelease" </dev/null) || status=000
		case "$status" in
		200)
			wanted="$wanted${wanted:+
}Types: deb
URIs: $uri
Suites: $suite
Components: $components
Signed-By: /etc/apt/keyrings/$key
"
			keys="$keys $key"
			;;
		404)
			echo "debug: $uri has published nothing for $suite yet, so it is left out of $list_file" >&2
			;;
		*)
			echo "error: $uri answered HTTP $status for dists/$suite/InRelease" >&2
			return 1
			;;
		esac
	done
	if [ -z "$wanted" ]; then
		if [ "$optional" != optional ]; then
			echo "error: no channel of $name has published packages for Ubuntu ${VERSION_CODENAME:-(no codename)}; .chezmoidata/apt-sources.toml lists its suites" >&2
			return 1
		fi
		APT_UNPUBLISHED_SOURCES="$APT_UNPUBLISHED_SOURCES$name "
		if [ -e "$list_file" ]; then
			sudo rm -f "$list_file"
			echo "notice: removed $list_file, as no channel of $name has published anything for Ubuntu ${VERSION_CODENAME:-(no codename)}" >&2
		fi
		echo "notice: no channel of $name has published packages for Ubuntu ${VERSION_CODENAME:-(no codename)}, so this host goes without them" >&2
		return 0
	fi
	wanted="# Written by chezmoi from .chezmoidata/apt-sources.toml; edits here are lost.
$wanted"
	sudo install -d -m 755 /etc/apt/keyrings
	for key in $keys; do
		key_file="/etc/apt/keyrings/$key"
		if [ "$(cat "$key_file" 2>/dev/null)" != "$(apt_source_key "$key")" ]; then
			apt_source_key "$key" | sudo tee "$key_file" >/dev/null
			sudo chmod 644 "$key_file"
			echo "notice: installed $name's signing key ($key_file)" >&2
		fi
	done
	if [ "$(cat "$list_file" 2>/dev/null)" = "$(printf '%s' "$wanted")" ]; then
		echo "debug: $list_file is up to date" >&2
	else
		printf '%s' "$wanted" | sudo tee "$list_file" >/dev/null
		sudo chmod 644 "$list_file"
		echo "notice: wrote $list_file ($(printf '%s' "$wanted" | sed -n 's|^URIs: .*/||p' | tr '\n' ' ' | sed 's/ $//'))" >&2
	fi
}
