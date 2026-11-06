# .chezmoidata/fedora-system-packages.toml as this host takes it: entries
# with gui = true are left out on a headless host, entries with an arch list
# on any other arch. Shared by 00-linux/020-dnf-packages (dnf, package-mode
# Fedora) and 02-bluefin/020-rpm-ostree-packages (rpm-ostree, Bluefin).
{{- $selected := list }}
{{- range .fedoraSystem.packages }}
{{-   $arch := get . "arch" }}
{{-   if not (or (and (get . "gui") $.useHeadless) (and $arch (not (has $.chezmoi.arch $arch)))) }}
{{-     $selected = append $selected . }}
{{-   end }}
{{- end }}
{{- $coprs := list }}
{{- range $selected }}
{{-   if get . "copr" }}
{{-     $coprs = append $coprs (get . "copr") }}
{{-   end }}
{{- end }}
FEDORA_SYSTEM_PACKAGES=(
{{- range $selected }}
	{{ .name }}
{{- end }}
)
FEDORA_SYSTEM_COPRS=(
{{- range uniq $coprs }}
	{{ . }}
{{- end }}
)

# Enables every COPR in FEDORA_SYSTEM_COPRS by writing the .repo file COPR
# serves for it into /etc/yum.repos.d, under the name `dnf copr enable` gives
# it, so `dnf copr list` and `dnf copr disable` know it. That needs no copr
# plugin for dnf, and rpm-ostree reads the same directory. The file names
# $releasever and $basearch, not this release, so it outlives an upgrade.
# Needs sudo; call it after require_sudo.
enable_fedora_system_coprs() {
	local copr owner project repo_file url repo
	for copr in "${FEDORA_SYSTEM_COPRS[@]}"; do
		owner=${copr%%/*}
		project=${copr#*/}
		repo_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${owner}:${project}.repo"
		if [ -f "$repo_file" ]; then
			echo "debug: COPR $copr is already enabled" >&2
			continue
		fi
		url="https://copr.fedorainfracloud.org/coprs/${owner}/${project}/repo/fedora-${VERSION_ID}/${owner}-${project}-fedora-${VERSION_ID}.repo"
		# Fetched whole before anything is written, so a failed download
		# leaves no half a repo file behind.
		repo=$(curl -fsSL "$url")
		printf '%s\n' "$repo" | sudo tee "$repo_file" >/dev/null
		sudo chmod 644 "$repo_file"
		echo "notice: enabled COPR $copr ($repo_file)" >&2
	done
}
