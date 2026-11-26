{{- /* Where brew fetches bottles from, for every host that runs brew: mainline
       and era-pinned macOS alike, and Linux. Included at the top level of
       posix-preamble.sh and dot_commonprofile.tmpl as
         template "brew-mirror-env.sh" .brewMirror
       with the account from .chezmoidata/brew-mirror.toml, so it has to work
       in bash 3.2 and zsh alike. Reasoning, and what each pinned brew does
       with these variables, in docs/brew-mirror.md.

       Two sources: the Nexus proxy of ghcr.io, and ghcr.io itself. A host
       starts on the mirror; a GitHub-hosted Actions runner starts on ghcr.io,
       which is decided when this runs, not when chezmoi renders it -- the
       container images and WSL tarballs are built on a runner and ship the
       rendered .commonprofile, and the machine they end up on is not one.
       RUNNER_ENVIRONMENT is GitHub's own variable ("github-hosted" or
       "self-hosted"); the Docker builds and the WSL chroot do not inherit the
       runner's environment, so docker-publish.yml and wsl-package.yml hand it
       through explicitly, along with the runner's token as
       DOTFILES_GITHUB_TOKEN.

       Nothing here defines `brew` itself: once a function by that name
       exists, `command -v brew` finds it whether or not brew is installed.
       posix-preamble.sh and dot_commonprofile.tmpl each define it, at the
       point where that is safe, as a call to _brew_fetching. */ -}}
# Bottles and portable-ruby come from the Nexus proxy of ghcr.io (read-only
# account, Basic auth) or from ghcr.io itself; whichever is not answering,
# brew gets the other. See _brew_fetching below and docs/brew-mirror.md.
_BREW_MIRROR_DOMAIN="{{ .artifact_domain }}"
_BREW_MIRROR_AUTH="{{ printf "%s:%s" .user .password | b64enc }}"
_BREW_GHCR_ROOT="https://ghcr.io/v2/"
# The last pick, shared by every hookscript of an apply and every shell; see
# _brew_source_pick.
_BREW_SOURCE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/brew-source"
if [ "${RUNNER_ENVIRONMENT:-}" = "github-hosted" ]; then
    _BREW_SOURCE_PRIMARY=ghcr
    _BREW_SOURCE_SECONDARY=mirror
else
    _BREW_SOURCE_PRIMARY=mirror
    _BREW_SOURCE_SECONDARY=ghcr
fi

_brew_source_name() {
    case "$1" in
    mirror) printf 'the bottle mirror (%s)\n' "${_BREW_MIRROR_DOMAIN%%/repository/*}" ;;
    *) printf 'ghcr.io\n' ;;
    esac
}

# Point brew at one source. The variables are unset, never set empty: brew
# 3.x/4.x test the domain for presence, and an empty one rewrites every bottle
# URL to `/v2/...`.
_brew_source_use() {
    case "$1" in
    mirror)
        export HOMEBREW_ARTIFACT_DOMAIN="$_BREW_MIRROR_DOMAIN"
        export HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN="$_BREW_MIRROR_AUTH"
        # brew 6+ would retry each bottle on ghcr.io, but with the mirror's
        # Basic header, which ghcr.io refuses (401). The retry that works is
        # _brew_fetching's, which switches the credentials along with the host.
        export HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1
        # brew prefers a bearer token over the Basic one, and the mirror takes
        # nothing but Basic.
        unset HOMEBREW_DOCKER_REGISTRY_TOKEN
        ;;
    ghcr)
        unset HOMEBREW_ARTIFACT_DOMAIN HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK
        # On a runner, its own token, so the pulls do not count against the
        # anonymous limit that every job on the runner's IP shares. ghcr.io
        # takes a GitHub token as `Authorization: Bearer <base64(token)>` (the
        # raw token gets 403, Basic gets 401), which is exactly what brew sends
        # for this variable. Without one brew sends its anonymous `Bearer QQ==`.
        if [ -n "${DOTFILES_GITHUB_TOKEN:-}" ]; then
            HOMEBREW_DOCKER_REGISTRY_TOKEN="$(printf '%s' "$DOTFILES_GITHUB_TOKEN" | base64 | tr -d '\n')"
            export HOMEBREW_DOCKER_REGISTRY_TOKEN
        else
            unset HOMEBREW_DOCKER_REGISTRY_TOKEN
        fi
        ;;
    *)
        return 1
        ;;
    esac
    _BREW_SOURCE="$1"
}

# Whether a source answers. The mirror has to accept the account (200 at the
# registry root); ghcr.io's root answers 401 to an anonymous request whenever
# it is up, which costs no token and no pull.
_brew_source_up() {
    local curl code
    curl=curl
    # The era Macs force brew's own curl (brew-era-env.sh): Apple's on 10.15
    # and 11 cannot reach the TLS 1.3-only mirror, but brew does not use it.
    if [ -n "${HOMEBREW_FORCE_BREWED_CURL:-}" ] && [ -x "${HOMEBREW_PREFIX:-/nonexistent}/opt/curl/bin/curl" ]; then
        curl="$HOMEBREW_PREFIX/opt/curl/bin/curl"
    fi
    case "$1" in
    mirror)
        code="$("$curl" -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 -m 5 \
            -H "Authorization: Basic $_BREW_MIRROR_AUTH" "$_BREW_MIRROR_DOMAIN/v2/" 2>/dev/null)"
        [ "$code" = 200 ]
        ;;
    ghcr)
        code="$("$curl" -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 -m 5 "$_BREW_GHCR_ROOT" 2>/dev/null)"
        [ "$code" = 200 ] || [ "$code" = 401 ]
        ;;
    *)
        return 1
        ;;
    esac
}

# A pick from the last ten minutes, if there is one.
_brew_source_cached() {
    local src stamp now
    [ -r "$_BREW_SOURCE_CACHE" ] || return 1
    read -r src stamp < "$_BREW_SOURCE_CACHE" 2>/dev/null || return 1
    case "$stamp" in '' | *[!0-9]*) return 1 ;; esac
    now="$(date +%s)"
    [ "$now" -ge "$stamp" ] && [ $((now - stamp)) -lt 600 ] || return 1
    case "$src" in
    mirror | ghcr) printf '%s\n' "$src" ;;
    *) return 1 ;;
    esac
}

# Best effort: a pick that cannot be written down is only asked for again.
# The `|| true` is for the hookscripts' `bash -e`, which a failed last command
# of an && list would otherwise end.
_brew_source_save() {
    { mkdir -p "${_BREW_SOURCE_CACHE%/*}" &&
        printf '%s %s\n' "$_BREW_SOURCE" "$(date +%s)" > "$_BREW_SOURCE_CACHE"; } 2>/dev/null || true
}

# Pick the source by asking, unless a pick from the last ten minutes stands:
# the primary if it answers, else the secondary. The pick is remembered, so an
# apply probes once rather than in every hookscript, and a source that was
# down is asked again ten minutes on.
_brew_source_pick() {
    local src
    if src="$(_brew_source_cached)"; then
        _brew_source_use "$src"
        return 0
    fi
    if _brew_source_up "$_BREW_SOURCE_PRIMARY"; then
        _brew_source_use "$_BREW_SOURCE_PRIMARY"
    elif _brew_source_up "$_BREW_SOURCE_SECONDARY"; then
        echo "warning: $(_brew_source_name "$_BREW_SOURCE_PRIMARY") is not answering; brew bottles come from $(_brew_source_name "$_BREW_SOURCE_SECONDARY") instead" >&2
        _brew_source_use "$_BREW_SOURCE_SECONDARY"
    else
        # Not remembered: the next brew asks again.
        echo "warning: neither the bottle mirror nor ghcr.io is answering; trying $(_brew_source_name "$_BREW_SOURCE_PRIMARY") anyway" >&2
        _brew_source_use "$_BREW_SOURCE_PRIMARY"
        return 0
    fi
    _brew_source_save
}

# brew, for the commands that fetch bottles, with the source picked first and
# one retry from the other source if the command fails -- which is what covers
# a source that dies partway through, or a single bottle it cannot serve.
# Everything else (list, --prefix, shellenv, services, trust, gem, ...) goes
# straight to brew.
# `env` bypasses our shell function without bash 3.2's `command` builtin:
# under `set -e`, that builtin can exit on a failed brew even in an `if`
# condition or an && list, breaking absent-package checks and the retry.
# Handle nonzero exits explicitly here too, for nested bash 3.2 functions.
_brew_fetching() {
    case "${1:-}" in
    install | reinstall | upgrade | fetch | bundle) ;;
    *)
        env brew "$@" || return $?
        return 0
        ;;
    esac
    _brew_source_pick
    env brew "$@" && return 0
    local rc=$? other="$_BREW_SOURCE_SECONDARY"
    [ "$_BREW_SOURCE" = "$_BREW_SOURCE_SECONDARY" ] && other="$_BREW_SOURCE_PRIMARY"
    if _brew_source_up "$other"; then
        echo "warning: brew $1 failed with bottles from $(_brew_source_name "$_BREW_SOURCE"); retrying with $(_brew_source_name "$other")" >&2
        _brew_source_use "$other"
        _brew_source_save
        env brew "$@" || return $?
        return 0
    fi
    return "$rc"
}

# Every brew sees a source from the start, with no network round trip: the
# last pick if it is recent, else the primary. Asking happens only where
# bottles are about to be fetched (_brew_fetching, posix-preamble-brew.sh and
# the brew installer in homebrew-install.sh).
_brew_source_use "$(_brew_source_cached || printf '%s\n' "$_BREW_SOURCE_PRIMARY")"
