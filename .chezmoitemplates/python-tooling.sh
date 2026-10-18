{{- $era := "mainline" }}
{{- if eq .chezmoi.os "darwin" }}
{{- $pin := index .brewTiers.legacy (printf "%s-%s" .macos.series .chezmoi.arch) | default dict }}
{{- $era = get $pin "era" | default "mainline" }}
{{- end }}
{{- $macportsUv := has $era (list "catalina" "bigsur" "monterey") }}
{{- $brew314 := has "3.14" (index .tooling.pythonVersions $era) }}
# The tools are .chezmoidata/python-tools.toml, shared with 00-nt/500-python.
# Prefer the host's Homebrew snapshot for equivalent tools; the per-era
# audit is in docs/tooling.md.
BREW_PYTHON_TOOLS=()
BREW_UV_REPLACEMENTS=()
{{- $uvTools := list }}
{{- range .pythonTools.packages }}
{{-   $os := get . "os" }}
{{-   if or (not $os) (has $.chezmoi.os $os) }}
{{-     $formula := includeTemplate "tool-brew-provider" (dict "tool" . "field" "brew" "era" $era "os" $.chezmoi.os "macosMajor" $.macos.major) | trim }}
{{-     if $formula }}
BREW_PYTHON_TOOLS+=({{ $formula }})
BREW_UV_REPLACEMENTS+=({{ .name }})
{{-     else }}
{{-       $uvTools = append $uvTools . }}
{{-     end }}
{{-   end }}
{{- end }}
brew install -q --formula "${BREW_PYTHON_TOOLS[@]}"

{{- if $macportsUv }}
# 017-macports-packages supplies uv: absent before 2024, and Monterey's
# pinned 0.1.21 predates `uv tool`. Select it explicitly even after a migration
# from the old Homebrew uv, which can still be installed on this host.
uv() { /opt/local/bin/uv "$@"; }
{{- else }}
brew install -q uv
{{- end }}

# Remove only tools whose replacements installed successfully above. Otherwise
# ~/.local/bin can continue to shadow Homebrew's executables after this change.
installed_uv_tools="$(uv tool list)"
for tool in "${BREW_UV_REPLACEMENTS[@]}"; do
	if printf '%s\n' "$installed_uv_tools" | grep -q "^$tool "; then
		uv tool uninstall "$tool"
	fi
done

{{- if $brew314 }}
# Installed by 020-brew-packages on macOS or 030-brew-extras on Linux from
# the same tooling.pythonVersions data. Never select Rosetta/system 3.14.
PYTHON314="$(brew --prefix python@3.14)/bin/python3.14"
{{- else }}
# This snapshot predates 3.14. 017 supplies a native MacPorts build with its
# headers, using the existing fallback for runtimes absent from the snapshot.
PYTHON314=/opt/local/bin/python3.14
{{- end }}
{{- if has $era (list "catalina" "bigsur" "monterey") }}
PYTHON313=/opt/local/bin/python3.13  # 017; RenderCV's pydantic-core has no 3.14 wheel
{{- else }}
PYTHON313=cp313
{{- end }}
{{- if has $era (list "catalina" "bigsur") }}
PYTHON312=/opt/local/bin/python3.12  # 017; Frida's intentionally pinned runtime
{{- else }}
PYTHON312=cp312
{{- end }}

# Everything brew does not supply in this era. Failures propagate through the
# hook's bash -e instead of silently skipping an older machine.
{{- range $uvTools }}
{{-   $python := get . "python" }}
{{-   if regexMatch "^3\\.[0-9]+$" $python }}
{{-     if not (has $python (list "3.12" "3.13" "3.14")) }}
{{-       fail (printf "python-tools.toml: %s asks for Python %s, but only 3.12, 3.13 and 3.14 have an interpreter picked per era" .name $python) }}
{{-     end }}
{{-     $python = printf "$PYTHON%s" (replace "." "" $python) }}
{{-   end }}
uv tool install{{ if $python }} --python "{{ $python }}"{{ end }} -q{{ range (get . "with" | default list) }} --with {{ quote . }}{{ end }} {{ get . "spec" | default .name | quote }}
{{- end }}
uv tool upgrade --quiet --all
