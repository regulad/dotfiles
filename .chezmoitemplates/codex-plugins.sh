# Codex CLI plugin bootstrap, shared by Linux and macOS; Windows counterpart:
# .chezmoiscripts/00-nt/run_after_812-codex-plugins.cmd.
# https://wakatime.com/codex-cli-plugin
# Run on every apply so a missing/older Codex can be retried on the next apply.
# Append-only: leave other plugins and the CLI-owned configuration alone.
if ! command -v codex &>/dev/null; then
	echo "note: codex is not installed, skipping Codex plugin bootstrap" >&2
	exit 0
fi
if ! codex plugin add --help >/dev/null 2>&1; then
	echo "warning: update Codex to a version supporting 'plugin add' to install WakaTime" >&2
	exit 0
fi

marketplaces=$(codex plugin marketplace list) || exit 1
if ! printf '%s\n' "$marketplaces" | grep -qFw -- wakatime; then
	codex plugin marketplace add wakatime/codex-cli-wakatime || exit 1
fi
# JSON output excludes uninstalled plugins unless --available is supplied.
plugins=$(codex plugin list --marketplace wakatime --json) || exit 1
if ! printf '%s\n' "$plugins" | grep -qF -- '"codex-cli-wakatime"'; then
	codex plugin add codex-cli-wakatime@wakatime || exit 1
fi
# The plugin reads ~/.wakatime.cfg, already provisioned by this repository.
# Codex may request review/trust of plugin hooks on the next interactive start.
