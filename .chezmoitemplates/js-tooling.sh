{{- $era := "mainline" }}
{{- if eq .chezmoi.os "darwin" }}
{{- $pin := index .brewTiers.legacy (printf "%s-%s" .macos.series .chezmoi.arch) | default dict }}
{{- $era = get $pin "era" | default "mainline" }}
{{- end }}
brew install -q pnpm

# pnpm 11 moved its global binaries into PNPM_HOME/bin. Older pinned pnpm
# releases require PNPM_HOME itself on PATH before any global command works.
{{- if eq .chezmoi.os "darwin" }}
export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
{{- else }}
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
{{- end }}
PNPM_MAJOR="$(pnpm --version | cut -d. -f1)"
if [ "$PNPM_MAJOR" -ge 11 ]; then
	PNPM_BIN="$PNPM_HOME/bin"
else
	PNPM_BIN="$PNPM_HOME"
fi
case ":$PATH:" in
	*":$PNPM_BIN:"*) ;;
	*) export PATH="$PNPM_BIN:$PATH" ;;
esac
mkdir -p "$PNPM_BIN"

# The packages are .chezmoidata/pnpm-tools.toml, shared with
# 00-nt/570-pnpm-tooling: brew's formula or cask where this era has one,
# pnpm's package otherwise.
BREW_JS_TOOLS=()
BREW_PNPM_REPLACEMENTS=()
PNPM_CLI_PACKAGES=()
{{- $casks := list }}
{{- $brewMermaid := false }}
{{- range .pnpmTools.packages }}
{{-   $os := get . "os" }}
{{-   if or (not $os) (has $.chezmoi.os $os) }}
{{-     $provider := dict "tool" . "era" $era "os" $.chezmoi.os "macosMajor" $.macos.major }}
{{-     $cask := includeTemplate "tool-brew-provider" (merge (dict "field" "brewCask") $provider) | trim }}
{{-     $formula := includeTemplate "tool-brew-provider" (merge (dict "field" "brew") $provider) | trim }}
{{-     if $cask }}
{{-       $casks = append $casks $cask }}
BREW_PNPM_REPLACEMENTS+=({{ quote .pnpm }})
{{-     else if $formula }}
BREW_JS_TOOLS+=({{ $formula }})
BREW_PNPM_REPLACEMENTS+=({{ quote .pnpm }})
{{-       if eq .pnpm "@mermaid-js/mermaid-cli" }}
{{-         $brewMermaid = true }}
{{-       end }}
{{-     else }}
PNPM_CLI_PACKAGES+=({{ printf "%s@latest" .pnpm | quote }})
{{-     end }}
{{-   end }}
{{- end }}
brew install -q --formula "${BREW_JS_TOOLS[@]}"
{{- if $casks }}
brew install -q --cask {{ join " " $casks }}
{{- end }}
{{- if $brewMermaid }}

# Homebrew omits Puppeteer's browser download; its own mmdc test expects
# "Could not find Chrome". Preserve the working renderer the pnpm install
# provided by running this formula's bundled, version-matched installer.
# It reuses Puppeteer's user cache on subsequent applies.
mermaid_puppeteer="$(brew --prefix mermaid-cli)/libexec/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer"
if [ -f "$mermaid_puppeteer/install.mjs" ]; then
	node "$mermaid_puppeteer/install.mjs"
elif [ -f "$mermaid_puppeteer/install.js" ]; then
	node "$mermaid_puppeteer/install.js"
else
	echo "error: mermaid-cli's Puppeteer browser installer is missing" >&2
	exit 1
fi
{{- end }}

# Global removals can also run lifecycle scripts for retained dependencies.
# Configure builds and go-ios' npm-style prefix before any pnpm transaction.
PNPM_GLOBAL_DIR="$(pnpm root -g)"
mkdir -p "$PNPM_GLOBAL_DIR"
# Before pnpm 10 dependency builds were allowed by default, and older config
# commands do not all support --location project.
if [ "$PNPM_MAJOR" -ge 10 ]; then
	pnpm -C "$PNPM_GLOBAL_DIR" config set --location project dangerouslyAllowAllBuilds true
fi
export npm_config_prefix="$(dirname "$(pnpm bin -g)")"

# Only remove pnpm copies after their Homebrew replacements succeeded.
# Parse the dependency keys, not the presentation of `pnpm list`'s text tree.
pnpm_installed_json="$(pnpm list -g --depth 0 --json)"
pnpm_installed="$(python3 -c 'import json,sys; print("\n".join(sorted({name for project in json.loads(sys.argv[1]) for name in project.get("dependencies", {})})))' "$pnpm_installed_json")"
for package in "${BREW_PNPM_REPLACEMENTS[@]}"; do
	if printf '%s\n' "$pnpm_installed" | grep -Fxq "$package"; then
		pnpm remove -g "$package"
	fi
done

pnpm i -g "${PNPM_CLI_PACKAGES[@]}"
pnpm update --global

export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"
