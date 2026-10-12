#!/bin/bash
# Run with bash 3.2, current bash, or zsh as the first argument. No network,
# package installs, or real credentials: brew and registry probes are stubs.
set -euo pipefail
shell=${1:-/bin/bash}
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/brew-mirror-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
export BREW_TEST_DIR="$work"
export XDG_CACHE_HOME="$work/cache"
export DOTFILES_GITHUB_TOKEN=fixture
export RUNNER_ENVIRONMENT=

# Render the file directly so this check uses the requested source file.
chezmoi --source "$repo" execute-template --file \
    "$repo/.chezmoitemplates/brew-mirror-env.sh" \
    --override-data '{"artifact_domain":"https://mirror.invalid","user":"test","password":"test"}' \
    | tr -d '\r' > "$work/mirror.sh"

cat > "$work/brew" <<'STUB'
#!/bin/sh
if [ -n "${HOMEBREW_ARTIFACT_DOMAIN:-}" ]; then
    src=mirror
    [ -n "${HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN:-}" ] || exit 98
    [ -z "${HOMEBREW_DOCKER_REGISTRY_TOKEN:-}" ] || exit 98
else
    src=ghcr
    [ "${HOMEBREW_DOCKER_REGISTRY_TOKEN:-}" = Zml4dHVyZQ== ] || exit 98
    [ -z "${HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN:-}" ] || exit 98
fi
printf '%s\n' "$src" >> "$BREW_TEST_DIR/calls"
case "$1" in
list) exit 1 ;;
install)
    [ "$src" != "$BREW_FAIL_SOURCE" ] && [ "$BREW_FAIL_SOURCE" != both ] && exit 0
    [ "$src" = mirror ] && exit 41
    exit 47
    ;;
esac
exit 99
STUB
chmod +x "$work/brew"
export PATH="$work:$PATH"

cat > "$work/check.sh" <<'CHECK'
set -e
. "$BREW_TEST_DIR/mirror.sh"
_brew_source_up() { [ "$1" != "${BREW_DOWN:-}" ]; }
brew() { _brew_fetching "$@"; }
case "$1" in
probe)
    if ! brew list --formula podman && ! brew list --formula podman-compose; then
        exit 0
    fi
    exit 99
    ;;
*) brew install fixture ;;
esac
CHECK

check() {
    local name=$1 expected_rc=$2 expected_calls=$3 rc=0 calls
    : > "$work/calls"
    # A separate cache per case avoids a preceding fallback changing its start.
    export XDG_CACHE_HOME="$work/cache/$name"
    "$shell" -e "$work/check.sh" "$name" || rc=$?
    calls=$(tr '\n' ' ' < "$work/calls")
    if [ "$rc" != "$expected_rc" ] || [ "$calls" != "$expected_calls" ]; then
        echo "error: $name: exit $rc, calls '$calls'; expected $expected_rc, '$expected_calls'" >&2
        exit 1
    fi
    echo "notice: $name passed ($shell)"
}

export BREW_FAIL_SOURCE=mirror BREW_DOWN=
check probe 0 'mirror mirror '
check fallback 0 'mirror ghcr '
export BREW_FAIL_SOURCE=both
check failed-retry 47 'mirror ghcr '
export BREW_DOWN=ghcr
check unavailable-fallback 41 'mirror '
export BREW_FAIL_SOURCE=none BREW_DOWN=
check primary-success 0 'mirror '
export RUNNER_ENVIRONMENT=github-hosted BREW_FAIL_SOURCE=ghcr
check runner-fallback 0 'ghcr mirror '
