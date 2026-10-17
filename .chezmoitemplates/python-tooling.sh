{{- $era := "mainline" }}
{{- if eq .chezmoi.os "darwin" }}
{{- $pin := index .brewTiers.legacy (printf "%s-%s" .macos.series .chezmoi.arch) | default dict }}
{{- $era = get $pin "era" | default "mainline" }}
{{- end }}
{{- $macportsUv := has $era (list "catalina" "bigsur" "monterey") }}
{{- $brew314 := has "3.14" (index .tooling.pythonVersions $era) }}
{{- $brewRuff := ne $era "catalina" }}
{{- $brewTy := has $era (list "mainline" "current" "sonoma") }}
# Prefer the host's Homebrew snapshot for equivalent tools. Version/feature
# exceptions and the per-era audit are documented in docs/tooling.md.
BREW_PYTHON_TOOLS=(poetry hatch autopep8 pre-commit ansible ansible-lint yamllint oci-cli)
BREW_UV_REPLACEMENTS=(poetry hatch autopep8 pre-commit ansible-core ansible-lint yamllint oci-cli)
{{- if $brewRuff }}
BREW_PYTHON_TOOLS+=(ruff)
BREW_UV_REPLACEMENTS+=(ruff)
{{- end }}
{{- if $brewTy }}
BREW_PYTHON_TOOLS+=(ty)
BREW_UV_REPLACEMENTS+=(ty)
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

{{- if not $brewRuff }}
uv tool install -q ruff  # no formula at the Catalina pin
{{- end }}
{{- if not $brewTy }}
uv tool install -q ty  # absent from the pre-2026 snapshots
{{- end }}

# Keep these uv installs on every era: Homebrew cannot supply the requested
# extras, fork or versions, or has no formula for the tool. Failures propagate
# through the hook's bash -e instead of silently skipping an older machine.
uv tool install --python "pypy@3.11" -q --with "bgutil-ytdlp-pot-provider" "yt-dlp[pin,pin-curl-cffi,pin-secretstorage,pin-deno]"
uv tool install --python "$PYTHON314" -q keydive
uv tool install --python "$PYTHON313" -q "mangadex-downloader[optional]"
uv tool install --python cp310 -q "git+https://github.com/regulad/keymap-renderer.git@master"

# The binding must match the device's roothide frida-server 16.7.0. Frida 17
# has no roothide port; frida-tools' own range would drift to 16.7.19 without
# --with. Both constraints survive `uv tool upgrade --all` in the receipt.
uv tool install --python "$PYTHON312" -q --with "frida==16.7.0" "frida-tools==13.7.1"

# RenderCV 2.2 retains the desired schema. Its loose dependencies need caps:
# 0.5 removed a font it references, Click 8.2 changed make_metavar's signature,
# Rich <11 matches its declared compatibility range, and Jinja stays on 3.x.
uv tool install --python "$PYTHON313" -q \
	--with "rendercv-fonts<0.5" \
	--with "click<8.2" \
	--with "rich<11" \
	--with "jinja2<4" \
	"rendercv[full]@2.2"

uv tool install --python "$PYTHON314" -q pymobiledevice3
uv tool install --python "$PYTHON314" -q claude-swap
# Patch signing is enabled in dot_gitconfig.tmpl on every non-dummy host.
uv tool install --python "$PYTHON314" -q patatt
uv tool upgrade --quiet --all
