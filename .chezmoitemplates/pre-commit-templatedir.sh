# Has pre-commit write its own hooks/pre-commit into git's template directory
# (init.templateDir, dot_gitconfig.tmpl), which every `git init` and
# `git clone` copies into the new repository. The hook runs pre-commit where
# the repository has a .pre-commit-config.yaml and skips it elsewhere.
# 00-nt/502-pre-commit-templatedir is the Windows twin.
#
# Every apply, after 100-python-tooling has installed or upgraded the
# pre-commit formula: the hook is pre-commit's template for its own version,
# with the interpreter it runs under written in (brew's patch makes that an
# opt/ path, so it survives upgrades), and init-templatedir overwrites its own
# hook in place.
TEMPLATE_DIR="$HOME/.config/git/template"

if ! command -v pre-commit &>/dev/null; then
	echo "error: pre-commit is not on PATH; 100-python-tooling installs it" >&2
	exit 1
fi

# pre-commit's output, under this repo's prefixes.
relay() {
	printf '%s\n' "$1" | while IFS= read -r line; do
		case "$line" in
			"") ;;
			"[WARNING] "*) echo "warning: pre-commit: ${line#"[WARNING] "}" >&2 ;;
			*) echo "debug: pre-commit: $line" >&2 ;;
		esac
	done
}

# --hook-type, or pre-commit reads the hook types from a
# .pre-commit-config.yaml in the current directory, wherever the apply was
# started from.
if ! out="$(pre-commit init-templatedir --color never --hook-type pre-commit "$TEMPLATE_DIR" 2>&1)"; then
	relay "$out"
	echo "error: pre-commit init-templatedir failed" >&2
	exit 1
fi
relay "$out"
