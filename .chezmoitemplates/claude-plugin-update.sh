# Update pass for Claude Code plugins; runs on every apply, shared verbatim by
# the linux and macos hooks. The Windows half is
# .chezmoiscripts/00-nt/run_after_811-claude-plugin-update.cmd. Installation and
# the declared list live in the bootstrap (167 / 810), except for the Mac's
# xcode below; otherwise this pass only moves what is already installed
# forward. `claude plugin update` reports "restart required to apply", which is
# expected here and applies on the next Claude Code start.

if ! command -v claude &>/dev/null; then
	echo "notice: claude is not installed, skipping Claude Code plugin update" >&2
	exit 0
fi

echo "debug: updating Claude Code marketplaces" >&2
claude plugin marketplace update || echo "warning: marketplace update failed" >&2
{{- if and (eq .chezmoi.os "darwin") (ge (int .macos.major) 26) }}

# xcode (claude-plugins-official) is Apple's skills and Xcode's MCP bridge.
# Its marketplace entry builds it from the installed Xcode (`xcrun agent plugin
# path`), which needs Xcode 27, from macOS 26 on. Xcode arrives by hand
# (060-mac-app-store leaves it alone), at any time, so it is installed here on
# every apply once it is there, rather than by the bootstrap's one run per list
# change. Its server and skills need Xcode's MCP server in headless mode,
# which 171-xcode-mcp-server turns on; Xcode still asks about each agent.
if ! claude plugin list 2>/dev/null | grep -qF -- "xcode@"; then
	xcode_major="$(xcodebuild -version 2>/dev/null | awk 'NR == 1 { split($2, v, "."); print v[1] }')"
	if [ "${xcode_major:-0}" -ge 27 ] 2>/dev/null; then
		echo "debug: installing plugin xcode@claude-plugins-official" >&2
		claude plugin install xcode@claude-plugins-official -y || echo "warning: failed to install xcode@claude-plugins-official" >&2
	else
		echo "debug: no Xcode 27 or later, skipping the xcode plugin" >&2
	fi
fi
{{- end }}

# Kept in step with the bootstrap's PLUGINS list. `claude plugin update` needs
# an explicit plugin name (there is no update-all), and the guard skips any that
# a given machine has not installed; it matches "plugin@", as the bootstrap's
# does, so that sentry does not match sentry-cli.
for plugin in claude-code-wakatime ralph-loop codex vercel cloudflare sentry sentry-cli supabase onesignal \
	modern-web-guidance microsoft-docs chrome-devtools-mcp astral docker-skills typescript android-skills xcode \
	c-review rust-review modern-cpp static-analysis sharp-edges insecure-defaults variant-analysis \
	differential-review supply-chain-risk-auditor testing-handbook-skills property-based-testing dwarf-expert \
	yara-authoring clangd-lsp gopls-lsp rust-analyzer-lsp jdtls-lsp typescript-lsp ruby-lsp; do
	if claude plugin list 2>/dev/null | grep -qF -- "$plugin@"; then
		echo "debug: updating plugin $plugin" >&2
		claude plugin update "$plugin" || echo "warning: failed to update $plugin" >&2
	fi
done
