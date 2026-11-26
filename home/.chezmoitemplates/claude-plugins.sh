# Claude Code plugin bootstrap, shared verbatim by the linux and macos hooks.
# The Windows half is
# .chezmoiscripts/00-nt/run_onchange_after_810-claude-plugins.cmd, which does
# the same steps against the same list. Ongoing updates are a separate
# every-apply pass, claude-plugin-update.sh (168 / 811).
#
# Why this is a script and not part of the ~/.claude.json / settings.json merge
# templates (claude-code-config.json / claude-settings.json): provisioning a
# plugin is not a config write. `claude plugin marketplace add` git-clones a
# repo, and `claude plugin install` fetches an archive and -- for
# command-installed plugins -- runs a marketplace-declared command, which a
# modify_ merge template cannot do. The CLI then records installed-plugin state
# back into ~/.claude.json, mixed in with the oauth/history state the merge
# deliberately leaves alone. So the two are orthogonal: the merge owns the
# mcpServers slice, this owns the fetch/install side effects.
#
# Append-only by design: it installs what is declared below and never
# uninstalls. Claude auto-installs the official marketplace and dependency
# plugins on its own, so the "the list is the whole truth" prune that the
# vim/coc/lazy scripts run would fight the CLI and churn on every apply.
#
# The declared list is inlined below rather than kept in a separate data file,
# so editing it is what retriggers this run_onchange pass -- the same reasoning
# as the inlined :sync lines in the vim bootstrap.

if ! command -v claude &>/dev/null; then
	echo "notice: claude is not installed, skipping Claude Code plugin bootstrap" >&2
	exit 0
fi

# Each marketplace entry is "name|add-source"; each plugin entry is
# "plugin|marketplace". Names are what `... list` is grepped for, so they must
# match the marketplace/plugin identifiers, not the repo path. `plugin list`
# prints each as "plugin@marketplace", and the grep takes the "@" with it, so
# that sentry does not match sentry-cli.
#
# vercel comes from the official marketplace, not a marketplace of its own:
# that is where Vercel's installer (`npx plugins add vercel/vercel-plugin`)
# sends Claude Code. cloudflare comes from Cloudflare's own marketplace, as its
# README says (https://github.com/cloudflare/skills#claude-code); the official
# one carries it too, pinned to an older commit.
#
# Both Sentry plugins come from the official marketplace, Sentry's own repos
# having none for Claude Code to add. sentry (getsentry/plugin-claude) is
# installed for its skills: its MCP server, which signs in with OAuth, is
# shadowed by the user-scope server of the same URL in claude-code-config.json,
# which carries the Bitwarden token. sentry-cli (getsentry/cli) is skills for
# the `sentry` CLI from .chezmoidata/pnpm-tools.toml.
#
# supabase (supabase-community/supabase-plugin, through the official
# marketplace) is skills for Supabase and Postgres plus Supabase's MCP server,
# which signs in with OAuth. Like sentry's, that server is shadowed by a
# user-scope one of the same URL in claude-code-config.json, carrying the
# Bitwarden token.
#
# onesignal comes from OneSignal's own marketplace, as its README says
# (https://github.com/OneSignal/onesignal-agent-plugin); Claude Code's built-in
# anthropic-plugin-directory carries it too, pinned to an older commit. It is
# skills for adding OneSignal to an app, plus OneSignal's hosted MCP server,
# which takes OAuth and nothing else. That server is left signed out, as
# Vercel's is: no reminder asks for it, and /mcp signs in where it is wanted.
#
# modern-web-guidance comes from Google Chrome's own marketplace, googlechrome,
# as its README says (https://github.com/GoogleChrome/modern-web-guidance);
# claude-plugins-official pins it to v0.0.194, where Anthropic stopped updating
# third-party plugins there on 2026-10-12. It is two skills, current web
# platform practice and Chrome extensions, with no server and no hooks. The
# first looks guides up at use time with `npx modern-web-guidance@latest`,
# whose telemetry is turned off by DISABLE_TELEMETRY in .commonprofile.
#
# regulad (regulad/skills, its own marketplace) is Parker's: the always-on
# rules for agents, which its SessionStart and SubagentStart hooks add to
# every session and subagent, and the skills that go with them. It is the
# only place those rules live; dotfiles carries none of their text. Like the
# rest, it isn't pinned: every apply's update pass moves it to the latest
# commit (its rules exempt plugin marketplaces from SHA pins).
#
# The rest come from their makers' own marketplaces, the ones their READMEs
# name, and are in Codex too (codex-plugins.sh) unless said otherwise:
# - microsoft-docs (MicrosoftDocs/mcp): skills plus Microsoft Learn's MCP
#   server, https://learn.microsoft.com/api/mcp, which takes no sign-in.
# - chrome-devtools-mcp (ChromeDevTools/chrome-devtools-mcp, Claude Code only;
#   claude-plugins-official pins an older copy): debugging and performance
#   skills plus the DevTools MCP server, which npx runs at the plugin's own
#   version. Its usage statistics and update checks are off through the
#   CHROME_DEVTOOLS_MCP_* variables in .commonprofile; its CrUX lookups, which
#   send the URLs it traces to Google's CrUX API, are left on.
# - trailofbits (trailofbits/skills): only the security review, static
#   analysis, fuzzing and supply-chain plugins listed below. Others in it put
#   shims on PATH or hook every stop (modern-python, gh-cli, fp-check), or fetch
#   an unpinned server at use time (zeroize-audit). Their reviewer agents and
#   slash commands are Claude Code's alone.
# - astral (astral-sh/agent-plugins): ruff, ty and uv skills, plus ty as the
#   Python language server, run as `uvx ty@latest server`.
# - docker-skills (docker/skills): skills plus Docker's docs MCP server, which
#   takes no sign-in.
# - typescript (microsoft/typescript-skills) and android-skills
#   (android/skills): skills only.
# The Windows list adds dotnet and dotnet-upgrade (dotnet/skills): the .NET SDK
# is installed only there (00-nt/100-winget), and the dotnet plugin's C#
# language server runs through `dotnet dnx`, which the SDK has from 10 on.
# xcode is installed by claude-plugin-update.sh on Macs, not from this list.
#
# The *-lsp plugins give Claude the language servers nvim's init.lua enables:
# diagnostics after each edit, plus a read-only LSP tool for definitions and
# references. Each is only an .lsp.json naming the server; the binary comes
# from the package hooks, and one not on PATH just shows under /plugin ->
# Errors until it is. Python's comes from astral above instead, since the
# official pyright-lsp runs pyright, not the ty nvim runs; Kotlin is left out
# because its official plugin runs JetBrains kotlin-lsp, not fwcd's. The
# Windows list drops typescript-lsp and ruby-lsp: Claude Code spawns servers
# without a shell, which can't run their .cmd/.bat wrappers
# (https://github.com/anthropics/claude-code/issues/51191).
MARKETPLACES=(
	"regulad|regulad/skills"
	"wakatime|wakatime/claude-code-wakatime"
	"claude-plugins-official|anthropics/claude-plugins-official"
	"openai-codex|openai/codex-plugin-cc"
	"cloudflare|cloudflare/skills"
	"onesignal|OneSignal/onesignal-agent-plugin"
	"googlechrome|GoogleChrome/modern-web-guidance"
	"microsoft-docs-marketplace|MicrosoftDocs/mcp"
	"chrome-devtools-plugins|ChromeDevTools/chrome-devtools-mcp"
	"trailofbits|trailofbits/skills"
	"astral-sh|astral-sh/agent-plugins"
	"docker|docker/skills"
	"typescript-skills|microsoft/typescript-skills"
	"android-skills|android/skills"
)
PLUGINS=(
	"regulad|regulad"
	"claude-code-wakatime|wakatime"
	"ralph-loop|claude-plugins-official"
	"codex|openai-codex"
	"vercel|claude-plugins-official"
	"cloudflare|cloudflare"
	"sentry|claude-plugins-official"
	"sentry-cli|claude-plugins-official"
	"supabase|claude-plugins-official"
	"onesignal|onesignal"
	"modern-web-guidance|googlechrome"
	"microsoft-docs|microsoft-docs-marketplace"
	"chrome-devtools-mcp|chrome-devtools-plugins"
	"c-review|trailofbits"
	"rust-review|trailofbits"
	"modern-cpp|trailofbits"
	"static-analysis|trailofbits"
	"sharp-edges|trailofbits"
	"insecure-defaults|trailofbits"
	"variant-analysis|trailofbits"
	"differential-review|trailofbits"
	"supply-chain-risk-auditor|trailofbits"
	"testing-handbook-skills|trailofbits"
	"property-based-testing|trailofbits"
	"dwarf-expert|trailofbits"
	"yara-authoring|trailofbits"
	"astral|astral-sh"
	"docker-skills|docker"
	"typescript|typescript-skills"
	"android-skills|android-skills"
	"clangd-lsp|claude-plugins-official"
	"gopls-lsp|claude-plugins-official"
	"rust-analyzer-lsp|claude-plugins-official"
	"jdtls-lsp|claude-plugins-official"
	"typescript-lsp|claude-plugins-official"
	"ruby-lsp|claude-plugins-official"
)

for entry in "${MARKETPLACES[@]}"; do
	name="${entry%%|*}"
	src="${entry#*|}"
	if claude plugin marketplace list 2>/dev/null | grep -qF -- "$name"; then
		echo "debug: marketplace $name already configured" >&2
	else
		echo "debug: adding marketplace $name from $src" >&2
		claude plugin marketplace add "$src" || echo "warning: failed to add marketplace $name" >&2
	fi
done

for entry in "${PLUGINS[@]}"; do
	plugin="${entry%%|*}"
	marketplace="${entry#*|}"
	if claude plugin list 2>/dev/null | grep -qF -- "$plugin@"; then
		echo "debug: plugin $plugin already installed" >&2
	else
		echo "debug: installing plugin $plugin@$marketplace" >&2
		# -y is required off-TTY and auto-accepts any marketplace-declared
		# install command; all sources here are plain git repos.
		claude plugin install "$plugin@$marketplace" -y || echo "warning: failed to install $plugin@$marketplace" >&2
	fi
done
