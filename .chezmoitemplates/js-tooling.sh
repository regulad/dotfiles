{{- $era := "mainline" }}
{{- if eq .chezmoi.os "darwin" }}
{{- $pin := index .brewTiers.legacy (printf "%s-%s" .macos.series .chezmoi.arch) | default dict }}
{{- $era = get $pin "era" | default "mainline" }}
{{- end }}
{{- $brewMermaid := not (has $era (list "bigsur" "monterey")) }}
{{- $brewWrangler := has $era (list "mainline" "ventura" "current" "sonoma") }}
{{- $brewCline := and (has $era (list "mainline" "current" "sonoma")) (not (and (eq .chezmoi.os "darwin") (ge .macos.major 27))) }}
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

BREW_JS_TOOLS=(bitwarden-cli typescript bash-language-server yaml-language-server)
BREW_PNPM_REPLACEMENTS=("@bitwarden/cli" typescript bash-language-server yaml-language-server vercel)
# go-ios has no core formula. Core's `cf` is a different timestamp filter,
# not Cloudflare's cf CLI. Both therefore stay in pnpm on every era.
PNPM_CLI_PACKAGES=("go-ios@latest" "cf@latest")
{{- if eq $era "catalina" }}
PNPM_CLI_PACKAGES+=("typescript-language-server@latest")
{{- else }}
BREW_JS_TOOLS+=(typescript-language-server)
BREW_PNPM_REPLACEMENTS+=(typescript-language-server)
{{- end }}
{{- if $brewMermaid }}
BREW_JS_TOOLS+=(mermaid-cli)
BREW_PNPM_REPLACEMENTS+=("@mermaid-js/mermaid-cli")
{{- else }}
# Disabled in Big Sur's snapshot and absent from Monterey's.
PNPM_CLI_PACKAGES+=("@mermaid-js/mermaid-cli@latest")
{{- end }}
{{- if $brewWrangler }}
BREW_JS_TOOLS+=(cloudflare-wrangler)
BREW_PNPM_REPLACEMENTS+=(wrangler)
{{- else }}
# The older formula is wrangler-legacy v1 (disabled in the 2023/24 pins),
# not the Workers SDK CLI used by our projects.
PNPM_CLI_PACKAGES+=("wrangler@latest")
{{- end }}
{{- if $brewCline }}
# Core's 3.0.3 is deprecated but still installable; it excludes macOS 27.
BREW_JS_TOOLS+=(cline)
BREW_PNPM_REPLACEMENTS+=(cline)
{{- else }}
PNPM_CLI_PACKAGES+=("cline@latest")
{{- end }}
{{- if eq $era "sonoma" }}
BREW_JS_TOOLS+=(vercel)
{{- else if ne $era "mainline" }}
BREW_JS_TOOLS+=(vercel-cli)
{{- end }}
brew install -q --formula "${BREW_JS_TOOLS[@]}"
{{- if eq $era "mainline" }}
# Vercel moved from a formula to a CLI cask, available on Linux too.
brew install -q --cask vercel
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
