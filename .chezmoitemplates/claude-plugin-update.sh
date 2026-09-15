# Update pass for Claude Code plugins; runs on every apply, shared verbatim by
# the linux and macos hooks. The Windows half is
# .chezmoiscripts/00-nt/run_after_811-claude-plugin-update.cmd. Installation and
# the declared list live in the bootstrap (167 / 810); this pass only moves what
# is already installed forward. `claude plugin update` reports "restart required
# to apply", which is expected here and applies on the next Claude Code start.

if ! command -v claude &>/dev/null; then
	echo "note: claude is not installed, skipping Claude Code plugin update" >&2
	exit 0
fi

echo "note: updating Claude Code marketplaces" >&2
claude plugin marketplace update || echo "warning: marketplace update failed" >&2

# Kept in step with the bootstrap's PLUGINS list. `claude plugin update` needs
# an explicit plugin name (there is no update-all), and the guard skips any that
# a given machine has not installed.
for plugin in claude-code-wakatime ralph-loop; do
	if claude plugin list 2>/dev/null | grep -qF -- "$plugin"; then
		echo "note: updating plugin $plugin" >&2
		claude plugin update "$plugin" || echo "warning: failed to update $plugin" >&2
	fi
done
