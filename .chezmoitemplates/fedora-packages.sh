# .chezmoidata/fedora-packages.toml as this host takes it, shared by
# 00-linux/020-dnf-packages (dnf, package-mode Fedora),
# 00-linux/022-brew-packages (brew, atomic Fedora) and
# 02-bluefin/020-rpm-ostree-packages (rpm-ostree, atomic Fedora). Entries with
# gui = true are left out on a headless host, entries with an arch list on any
# other arch. wsl = false and native = true are decided here when the script
# runs, from the preamble's IS_WSL and CONTAINERIZED; an atomic host is
# neither, so brew's formulas don't depend on them.
{{- $dnf := list }}
{{- $dnfOffWsl := list }}
{{- $dnfNative := list }}
{{- $dnfErasing := list }}
{{- $layer := list }}
{{- $layerNative := list }}
{{- $brew := list }}
{{- $sourceOf := dict }}
{{- range .fedoraPackages.packages }}
{{-   $pkg := . }}
{{-   if not (or (hasKey $pkg "layer") (hasKey $pkg "brew")) }}
{{-     fail (printf "fedora-packages.toml: %s says neither layer nor brew, so how an atomic host gets it is undecided" $pkg.name) }}
{{-   end }}
{{-   with get $pkg "source" }}
{{-     if not (hasKey $.fedoraPackages.sources .) }}
{{-       fail (printf "fedora-packages.toml: %s comes from source %s, which [fedoraPackages.sources] does not define" $pkg.name .) }}
{{-     end }}
{{-   end }}
{{-   $arch := get $pkg "arch" }}
{{-   if not (or (and (get $pkg "gui") $.useHeadless) (and $arch (not (has $.chezmoi.arch $arch)))) }}
{{-     if or (not (hasKey $pkg "dnf")) (get $pkg "dnf") }}
{{-       if get $pkg "allowErasing" }}
{{-         $dnfErasing = append $dnfErasing $pkg.name }}
{{-       else if get $pkg "native" }}
{{-         $dnfNative = append $dnfNative $pkg.name }}
{{-       else if and (hasKey $pkg "wsl") (not (get $pkg "wsl")) }}
{{-         $dnfOffWsl = append $dnfOffWsl $pkg.name }}
{{-       else }}
{{-         $dnf = append $dnf $pkg.name }}
{{-       end }}
{{-     end }}
{{-     if get $pkg "layer" }}
{{-       if get $pkg "native" }}
{{-         $layerNative = append $layerNative $pkg.name }}
{{-       else }}
{{-         $layer = append $layer $pkg.name }}
{{-       end }}
{{-     else if get $pkg "brew" }}
{{-       if not (has (get $pkg "brew") $brew) }}
{{-         $brew = append $brew (get $pkg "brew") }}
{{-       end }}
{{-     end }}
{{-     with get $pkg "source" }}
{{-       $_ := set $sourceOf $pkg.name . }}
{{-     end }}
{{-   end }}
{{- end }}
FEDORA_DNF_PACKAGES=(
{{- range $dnf }}
	{{ . }}
{{- end }}
)
FEDORA_DNF_ERASING_PACKAGES=(
{{- range $dnfErasing }}
	{{ . }}
{{- end }}
)
FEDORA_LAYERED_PACKAGES=(
{{- range $layer }}
	{{ . }}
{{- end }}
)
FEDORA_BREW_FORMULAE=(
{{- range $brew }}
	{{ . }}
{{- end }}
)
# wsl = false: everywhere but WSL. native = true: on a machine of its own,
# neither WSL nor a container.
if [ "$IS_WSL" -ne 1 ]; then
	FEDORA_DNF_PACKAGES+=(
{{- range $dnfOffWsl }}
		{{ . }}
{{- end }}
	)
fi
if [ "$IS_WSL" -ne 1 ] && [ "$CONTAINERIZED" -ne 1 ]; then
	FEDORA_DNF_PACKAGES+=(
{{- range $dnfNative }}
		{{ . }}
{{- end }}
	)
	FEDORA_LAYERED_PACKAGES+=(
{{- range $layerNative }}
		{{ . }}
{{- end }}
	)
fi

# The source each package comes from, when it is not Fedora's own repos.
fedora_package_source() {
	case "$1" in
{{- range $name, $src := $sourceOf }}
	{{ $name }}) echo {{ $src | quote }} ;;
{{- end }}
	esac
}

# Enables every source (.chezmoidata/fedora-packages.toml's [sources]) the
# given packages come from, each once. Needs sudo; call it after require_sudo.
enable_fedora_sources() {
	local pkg src seen=" "
	for pkg in "$@"; do
		src=$(fedora_package_source "$pkg")
		[ -n "$src" ] || continue
		case "$seen" in
		*" $src "*) continue ;;
		esac
		seen="$seen$src "
		enable_fedora_source "$src" || return 1
	done
}

enable_fedora_source() {
	local key channels
	case "$1" in
{{- range $name, $src := .fedoraPackages.sources }}
{{-   if not (has $src.signed (list "packages" "metadata")) }}
{{-     fail (printf "fedora-packages.toml: source %s has signed = %q; it is \"packages\" or \"metadata\"" $name (toString $src.signed)) }}
{{-   end }}
	{{ $name }})
		# (read -d '' returns 1 at the heredoc's end, having no NUL to stop at.)
		IFS= read -r -d '' key <<'CHEZMOI_FEDORA_SOURCE_KEY' || true
{{ include (joinPath $.chezmoi.sourceDir ".chezmoitemplates" "keys" $src.key) | trim }}
CHEZMOI_FEDORA_SOURCE_KEY
		IFS= read -r -d '' channels <<'CHEZMOI_FEDORA_SOURCE_CHANNELS' || true
{{ range $src.channels }}{{ .id }} {{ .url }}
{{ end -}}
CHEZMOI_FEDORA_SOURCE_CHANNELS
		write_fedora_repo {{ $name | quote }} {{ $src.description | quote }} {{ $src.signed }} "$key" "$channels"{{ range (get $src "replaces" | default list) }} {{ . | quote }}{{ end }}
		;;
{{- end }}
	*)
		echo "error: $1 is not a source in .chezmoidata/fedora-packages.toml" >&2
		return 1
		;;
	esac
}

# One source: $1 its name, $2 its description, $3 what its key signs
# ("packages" or "metadata"), $4 the key, $5 its channels, one
# "<id> <baseurl>" per line, then any .repo files it replaces. Installs the
# key to /etc/pki/rpm-gpg/RPM-GPG-KEY-<name> and writes
# /etc/yum.repos.d/<name>.repo with a section for each channel whose metadata
# exists for this release ($releasever) and architecture ($basearch). A
# channel that answers 404 has published nothing for them yet and is left out;
# any other answer, or none, is an error, and changes nothing. The files it
# replaces go once it is written.
write_fedora_repo() {
	local name=$1 description=$2 signed=$3 key=$4 channels=$5
	shift 5
	local key_file="/etc/pki/rpm-gpg/RPM-GPG-KEY-$name" repo_file="/etc/yum.repos.d/$name.repo"
	local arch wanted="" id url probe status checks old
	if [ "$signed" = packages ]; then
		checks="gpgcheck=1
repo_gpgcheck=0"
	else
		checks="gpgcheck=0
repo_gpgcheck=1"
	fi
	arch=$(uname -m)
	while read -r id url; do
		[ -n "$id" ] || continue
		probe=${url//\$releasever/$VERSION_ID}
		probe=${probe//\$basearch/$arch}
		# -L, as dnf follows redirects too: COPR's downloads answer 301 to
		# its CDN. The status is the one at the end of them.
		status=$(curl -sSL -o /dev/null -w '%{http_code}' "${probe}repodata/repomd.xml") || status=000
		case "$status" in
		200)
			wanted="$wanted[$id]
name=$description ($id)
baseurl=$url
enabled=1
$checks
gpgkey=file://$key_file

"
			;;
		404)
			echo "debug: $id has published nothing for Fedora $VERSION_ID $arch yet, so it is left out of $repo_file" >&2
			;;
		*)
			echo "error: $id answered HTTP $status for ${probe}repodata/repomd.xml" >&2
			return 1
			;;
		esac
	done <<EOF
$channels
EOF
	if [ -z "$wanted" ]; then
		echo "error: no channel of $name has published packages for Fedora $VERSION_ID $arch" >&2
		return 1
	fi
	wanted="# Written by chezmoi from .chezmoidata/fedora-packages.toml; edits here are lost.
$wanted"
	if [ "$(cat "$key_file" 2>/dev/null)" != "$(printf '%s' "$key")" ]; then
		printf '%s' "$key" | sudo tee "$key_file" >/dev/null
		sudo chmod 644 "$key_file"
		echo "notice: installed $name's signing key ($key_file)" >&2
	fi
	if [ "$(cat "$repo_file" 2>/dev/null)" = "$(printf '%s' "$wanted")" ]; then
		echo "debug: $repo_file is up to date" >&2
	else
		printf '%s' "$wanted" | sudo tee "$repo_file" >/dev/null
		sudo chmod 644 "$repo_file"
		echo "notice: wrote $repo_file ($(printf '%s' "$wanted" | sed -n 's/^\[\(.*\)\]$/\1/p' | tr '\n' ' ' | sed 's/ $//'))" >&2
	fi
	for old in "$@"; do
		if [ -e "/etc/yum.repos.d/$old" ]; then
			sudo rm -f "/etc/yum.repos.d/$old"
			echo "notice: removed /etc/yum.repos.d/$old, which $repo_file replaces" >&2
		fi
	done
}
