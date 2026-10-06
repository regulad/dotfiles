# Codex CLI plugin bootstrap, shared by Linux and macOS; Windows counterpart:
# .chezmoiscripts/00-nt/run_after_812-codex-plugins.cmd.
# Run on every apply so a missing/older Codex, or a curated marketplace Codex
# has not synced yet, can be retried on the next apply.
# Append-only: leave other plugins and the CLI-owned configuration alone.
if ! command -v codex &>/dev/null; then
	echo "notice: codex is not installed, skipping Codex plugin bootstrap" >&2
	exit 0
fi
if ! codex plugin add --help >/dev/null 2>&1; then
	echo "warning: update Codex to a version supporting 'plugin add' to install plugins" >&2
	exit 0
fi

# Git marketplaces added here, "name|add-source":
#   wakatime    https://wakatime.com/codex-cli-plugin -- the plugin reads
#               ~/.wakatime.cfg, already provisioned by this repository.
#   cloudflare  https://github.com/cloudflare/skills#codex
MARKETPLACES=(
	"wakatime|wakatime/codex-cli-wakatime"
	"cloudflare|cloudflare/skills"
)
# "plugin|marketplace". The marketplace "curated" stands for OpenAI's curated
# one, resolved below. vercel comes from there because that is where Vercel's
# installer (`npx plugins add vercel/vercel-plugin`) sends Codex; the repo has
# no Codex marketplace of its own.
PLUGINS=(
	"codex-cli-wakatime|wakatime"
	"cloudflare|cloudflare"
	"vercel|curated"
)

failed=
# Capture output first so a failed list cannot be mistaken for an empty list.
if marketplaces=$(codex plugin marketplace list); then
	for entry in "${MARKETPLACES[@]}"; do
		name="${entry%%|*}"
		src="${entry#*|}"
		if ! printf '%s\n' "$marketplaces" | grep -q "^$name "; then
			echo "debug: adding Codex marketplace $name from $src" >&2
			codex plugin marketplace add "$src" || failed=1
		fi
	done
else
	failed=1
fi

# Codex clones OpenAI's curated marketplace (github.com/openai/plugins) by
# itself on an interactive start, and names it openai-curated under a ChatGPT
# login, openai-api-curated otherwise. Before that first start there is
# nothing to install from.
curated=
for name in openai-curated openai-api-curated; do
	if printf '%s\n' "$marketplaces" | grep -q "^$name "; then
		curated=$name
		break
	fi
done

for entry in "${PLUGINS[@]}"; do
	plugin="${entry%%|*}"
	marketplace="${entry#*|}"
	if [ "$marketplace" = curated ]; then
		if [ -z "$curated" ]; then
			echo "notice: Codex has not synced its curated marketplace yet, skipping $plugin; start codex once and re-apply" >&2
			continue
		fi
		marketplace=$curated
	fi
	# JSON output excludes uninstalled plugins unless --available is supplied.
	if ! plugins=$(codex plugin list --marketplace "$marketplace" --json); then
		failed=1
		continue
	fi
	if ! printf '%s\n' "$plugins" | grep -qF -- "\"$plugin@$marketplace\""; then
		echo "debug: installing Codex plugin $plugin@$marketplace" >&2
		codex plugin add "$plugin@$marketplace" || failed=1
	fi
done
# Codex may request review/trust of plugin hooks on the next interactive start.

if [ -n "$failed" ]; then
	echo "error: Codex plugin bootstrap failed; next apply will retry" >&2
	exit 1
fi
