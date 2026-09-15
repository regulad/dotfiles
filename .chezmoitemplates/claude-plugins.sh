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
	echo "note: claude is not installed, skipping Claude Code plugin bootstrap" >&2
	exit 0
fi

# Each marketplace entry is "name|add-source"; each plugin entry is
# "plugin|marketplace". Names are what `... list` is grepped for, so they must
# match the marketplace/plugin identifiers, not the repo path.
MARKETPLACES=(
	"wakatime|wakatime/claude-code-wakatime"
	"claude-plugins-official|anthropics/claude-plugins-official"
)
PLUGINS=(
	"claude-code-wakatime|wakatime"
	"ralph-loop|claude-plugins-official"
)

for entry in "${MARKETPLACES[@]}"; do
	name="${entry%%|*}"
	src="${entry#*|}"
	if claude plugin marketplace list 2>/dev/null | grep -qF -- "$name"; then
		echo "note: marketplace $name already configured" >&2
	else
		echo "note: adding marketplace $name from $src" >&2
		claude plugin marketplace add "$src" || echo "warning: failed to add marketplace $name" >&2
	fi
done

for entry in "${PLUGINS[@]}"; do
	plugin="${entry%%|*}"
	marketplace="${entry#*|}"
	if claude plugin list 2>/dev/null | grep -qF -- "$plugin"; then
		echo "note: plugin $plugin already installed" >&2
	else
		echo "note: installing plugin $plugin@$marketplace" >&2
		# -y is required off-TTY and auto-accepts any marketplace-declared
		# install command; both sources here are plain git repos.
		claude plugin install "$plugin@$marketplace" -y || echo "warning: failed to install $plugin@$marketplace" >&2
	fi
done
