#!/bin/bash
# /etc/oobe.sh -- first-run setup, invoked by WSL via oobe.command in
# /etc/wsl-distribution.conf the first time an interactive shell is opened in
# a freshly installed instance.
#
# ############################################################################
# THIS SCRIPT MUST NEVER EXIT NON-ZERO.
#
# WSL treats a non-zero exit from oobe.command as a failed first run and
# refuses to open a shell in the distribution -- there is no way back in short
# of `wsl --unregister`, which destroys the instance. Every failure path below
# therefore warns, explains how to retry, and exits 0. Do not "tidy this up"
# by adding `set -e`.
# ############################################################################
#
# What it does, following the *nix install sequence in README.md:
#
#   bw config server ...     point the CLI at the vaultwarden instance
#   bw login --apikey        authenticate (see the credential note below)
#   chezmoi init             regenerate ~/.config/chezmoi/chezmoi.toml *without*
#                            CHEZMOI_USE_DUMMY, flipping useDummySecrets to
#                            false -- the image was built with it true
#   chezmoi apply ~/key.txt  bootstrap the age identity
#   chezmoi apply            full apply: encrypted files, real secrets, and the
#                            WSL-only scriptlets that are masked everywhere else
#
# Every step is a no-op when its work is already done, so a re-run on an
# instance that is partly or fully set up picks up where the last one stopped:
# the server is only configured when it differs, the login is skipped when
# there is one, and chezmoi's applies are idempotent by nature.
#
# Credentials: `bw login --apikey` reads BW_CLIENTID and BW_CLIENTSECRET from
# the environment and prompts for them when absent. ~/.secrets/.bwrc defines
# exactly those two variables -- as bare KEY=VALUE, systemd EnvironmentFile
# syntax, deliberately without `export`, so the same file can back a unit's
# EnvironmentFile=. The inner script below reads the two values out of it and
# exports them; it does not source it (see read_bwrc there for why). It cannot
# exist yet inside a fresh instance -- that file is itself templated *out of*
# Bitwarden (private_dot_secrets/private_dot_bwrc.tmpl),
# so it only appears after an authenticated apply -- but the Windows host this
# instance runs on has already been provisioned by the same repo, so its copy
# is sitting at %USERPROFILE%\.secrets\.bwrc, reachable over DrvFs at
# /mnt/c/Users/<profile>/.secrets/.bwrc. That is preferred over prompting.
#
# Nothing secret is ever baked into the image: ~/.secrets/ and ~/key.txt are
# both masked by useDummySecrets during the build. The Windows copy is read at
# first run, from the user's own machine, and never written into the tarball.

set -u

DISTRO_USER="regulad.linux"
DISTRO_UID="1000"
BW_SERVER="https://vw.regulad.xyz"

say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

retry_hint() {
    warn "first-run setup did not complete."
    warn "you have a working shell; nothing is broken. re-run it any time with:"
    warn "    sudo /etc/oobe.sh"
    warn "or follow the manual sequence in ~/.local/share/chezmoi/README.md"
}

# /etc/wsl.conf sets [automount] enabled=true root=/mnt/, so C: should already
# be there. Checked rather than assumed because the Windows-side .bwrc lives on
# it, and a bare `[ -d /mnt/c ]` would be satisfied by an empty leftover
# directory with nothing mounted on it.
ensure_windows_drive() {
    if findmnt -rno TARGET /mnt/c >/dev/null 2>&1; then
        return 0
    fi
    warn "/mnt/c is not mounted; attempting to mount C: manually"
    mkdir -p /mnt/c
    mount -t drvfs C: /mnt/c 2>/dev/null || true
    findmnt -rno TARGET /mnt/c >/dev/null 2>&1
}

# Locate a .bwrc to source. Preference order:
#   1. this instance's own ~/.secrets/.bwrc  (present on a re-run)
#   2. the Windows host's, over DrvFs        (present on a genuine first run)
# Prints the path on stdout, or nothing if neither exists.
#
# The Windows profile is found by glob rather than by asking Windows for
# %USERPROFILE%: that would need interop, and interop is exactly what is
# unreliable at this point in a fresh instance -- the WSLInterop binfmt
# registration races systemd-binfmt, which is what 004-wsl-binfmt-interop.sh
# fixes, and that has not run yet on a first boot.
find_bwrc() {
    local candidate matches=() home
    home="$(getent passwd "$DISTRO_UID" | cut -d: -f6)"

    if [ -r "$home/.secrets/.bwrc" ]; then
        printf '%s\n' "$home/.secrets/.bwrc"
        return 0
    fi

    ensure_windows_drive || {
        warn "could not mount C:; falling back to prompting for API credentials"
        return 1
    }

    for candidate in /mnt/c/Users/*/.secrets/.bwrc; do
        [ -r "$candidate" ] && matches+=("$candidate")
    done

    case "${#matches[@]}" in
        0) return 1 ;;
        1) printf '%s\n' "${matches[0]}"; return 0 ;;
        *)
            # More than one Windows profile has been provisioned by this repo.
            # Guessing would be worse than asking.
            warn "several Windows profiles have a .bwrc:"
            printf '  %s\n' "${matches[@]}" >&2
            read -r -p "path to use (blank to type credentials instead): " chosen || chosen=""
            [ -n "$chosen" ] && [ -r "$chosen" ] && printf '%s\n' "$chosen" && return 0
            return 1
            ;;
    esac
}

# WSL_DISTRO_NAME is set only by WSL's own session bootstrap, and a re-run as
# `sudo /etc/oobe.sh` arrives without it, because sudo resets the environment.
# The apply needs it (see the inner script), so it is recovered from the
# nearest ancestor process that has it: the shell sudo was typed into. Only
# whether it is set matters to anything in this repo, not the name itself.
recover_wsl_distro_name() {
    local pid=$$ value depth=0
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 32 ]; do
        depth=$((depth + 1))
        value="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WSL_DISTRO_NAME=//p' | head -n 1)"
        if [ -n "$value" ]; then
            printf '%s\n' "$value"
            return 0
        fi
        pid="$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null)"
    done
    return 1
}

if ! getent passwd "$DISTRO_UID" >/dev/null 2>&1; then
    warn "uid $DISTRO_UID is missing from this image, which should be impossible."
    warn "skipping first-run setup."
    exit 0
fi

if [ -z "${WSL_DISTRO_NAME:-}" ]; then
    WSL_DISTRO_NAME="$(recover_wsl_distro_name || true)"
fi
if [ -z "${WSL_DISTRO_NAME:-}" ]; then
    warn "WSL_DISTRO_NAME is not set, and no parent process has it either;"
    warn "the apply would take this instance for a container. Run it from Windows instead:"
    warn "    wsl -d <this distribution> -u root -- /etc/oobe.sh"
    exit 0
fi

cat <<BANNER

  regulad/dotfiles -- WSL first run

  This instance already has every package, toolchain and dotfile baked in.
  What is left is the part that cannot be baked into a public image: your
  secrets.

  Credentials come from the Windows host's own .secrets/.bwrc where that is
  readable. Otherwise you will be asked for your Bitwarden API client id and
  secret, from ${BW_SERVER} under Account Settings -> Security ->
  Keys -> View API Key.

  Skipping is safe. You keep a fully working shell either way, and you can
  run 'sudo /etc/oobe.sh' whenever you like.

BANNER

read -r -p "Authenticate and apply secrets now? [Y/n] " reply || reply="n"
case "${reply:-Y}" in
    [Nn]*)
        say "skipped."
        warn "run 'sudo /etc/oobe.sh' when you are ready."
        exit 0
        ;;
esac

# Discovered here rather than before the prompt, because the multiple-profile
# branch asks a question of its own and there is no reason to ask it of someone
# who is about to decline anyway.
BWRC="$(find_bwrc || true)"
if [ -n "$BWRC" ]; then
    say "using API credentials from ${BWRC}"
else
    say "no .bwrc found; you will be prompted for API credentials"
fi

# The real work runs as the unprivileged user, in a login shell, via a script
# file rather than `runuser -c '<long string>'` -- quoting a heredoc through
# runuser's -c is a foot-gun, and anything passed on the command line would be
# visible in ps to every other user on the system.
#
# Write first, then hand it over. Doing the chown before the heredoc means
# root re-opens, with O_CREAT, a file it no longer owns inside /tmp -- which
# is world-writable and sticky -- and fs.protected_regular (2 on Ubuntu)
# denies exactly that, root included. The heredoc then failed with
# "Permission denied", leaving an empty script that runuser dutifully ran as
# a no-op, so OOBE reported success while having applied nothing.
inner="$(mktemp /tmp/oobe-inner.XXXXXX.sh)"

# The values the inner script needs from here go in as %q-quoted assignments
# ahead of its body, and the body is a quoted heredoc, so nothing in it is
# expanded by this shell and none of its `$` needs escaping.
{
    printf '#!/bin/bash\n'
    printf 'WSL_DISTRO_NAME=%q\n' "$WSL_DISTRO_NAME"
    printf 'BWRC=%q\n' "$BWRC"
    printf 'BW_SERVER=%q\n' "$BW_SERVER"
    cat <<'INNER'
set -u

# runuser -l starts a fresh login environment, which drops WSL's own exports.
# WSL_DISTRO_NAME has to survive: .chezmoiignore keys the WSL-only scriptlets
# (004-wsl-binfmt-interop, 006-wsl-gpu, 007-ssh-agent-relay) off it, and the
# posix preamble uses it to tell a real WSL session apart from a container --
# systemd-detect-virt reports "wsl" for both.
export WSL_DISTRO_NAME

# The .bwrc is read, not sourced. The Windows host's copy is rendered by
# chezmoi on Windows from a CRLF checkout (core.autocrlf), so sourcing it left
# a CR on the end of each value and bw rejected the id with "bad client_id".
# Only the two keys are taken, each line's CR is dropped, and so is the pair
# of quotes the template puts around each value, as systemd's
# EnvironmentFile= drops them. Path only -- the credentials themselves are
# never passed through argv or the environment of this script, so they never
# appear in ps for other users.
read_bwrc() {
    local line key value
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in
            BW_CLIENTID=*|BW_CLIENTSECRET=*) ;;
            *) continue ;;
        esac
        key="${line%%=*}"
        value="${line#*=}"
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        printf -v "$key" '%s' "$value"
    done < "$1"
}

BW_CLIENTID=
BW_CLIENTSECRET=
if [ -n "$BWRC" ] && [ -r "$BWRC" ]; then
    read_bwrc "$BWRC"
    if [ -n "$BW_CLIENTID" ] && [ -n "$BW_CLIENTSECRET" ]; then
        export BW_CLIENTID BW_CLIENTSECRET
        echo "debug: API credentials loaded from $BWRC" >&2
    else
        echo "warning: $BWRC did not define BW_CLIENTID/BW_CLIENTSECRET; will prompt" >&2
    fi
fi
if [ -z "${BW_CLIENTID:-}" ] || [ -z "${BW_CLIENTSECRET:-}" ]; then
    unset BW_CLIENTID BW_CLIENTSECRET
fi

# `bw config server` refuses to change the server while an account is logged
# in ("Logout required before server config update."), even to the URL it
# already has, so a re-run used to stop here. Reading it is always allowed,
# so it is only set when it differs.
current_server="$(bw config server 2>/dev/null || true)"
if [ "${current_server%/}" = "${BW_SERVER%/}" ]; then
    echo "debug: bw already points at $BW_SERVER" >&2
elif bw login --check >/dev/null 2>&1; then
    echo "error: bw is logged in to ${current_server:-another server}, not $BW_SERVER; run 'bw logout' first" >&2
    exit 1
else
    bw config server "$BW_SERVER" || exit 1
fi

if bw login --check >/dev/null 2>&1; then
    echo "debug: already logged in to Bitwarden" >&2
else
    bw login --apikey || exit 1
fi

# chezmoi's own [bitwarden] unlock = "auto" handles the vault session for
# templating; this just fails fast with a clear message if the vault will not
# unlock, rather than letting every bitwarden template lookup fail one by one.
if ! bw unlock --check >/dev/null 2>&1; then
    BW_SESSION="$(bw unlock --raw)" || exit 1
    export BW_SESSION
fi

# Regenerate the config with useDummySecrets = false. The image was built with
# CHEZMOI_USE_DUMMY=1, and that value is baked into chezmoi.toml, not re-derived.
chezmoi init || exit 1

# age identity first -- everything encrypted depends on it.
chezmoi apply "$HOME/key.txt" || exit 1

# Full apply. Expected to do real work here: encrypted files, real secrets, and
# the WSL-only scriptlets, none of which ran during the image build.
chezmoi apply || exit 1
INNER
} > "$inner"

# Only now that the content is written. runuser invokes it as `bash '$inner'`,
# so this needs to be readable by the user rather than executable, but 0700
# plus the chown gives both and keeps it unreadable to anyone else -- the
# script carries no credentials, only the path to them, but there is no reason
# to widen it.
chmod 0700 "$inner"
chown "$DISTRO_USER" "$inner"

# This script deliberately runs without `set -e`, so a failed heredoc above
# would otherwise sail past and hand runuser an empty file: a silent no-op
# reported as a successful first-run apply. Fail loudly instead.
if [ ! -s "$inner" ]; then
    say "error: could not write ${inner}; nothing was applied."
    retry_hint
    exit 1
fi

say "running first-run apply as ${DISTRO_USER} (this will take a few minutes)"

if runuser -l "$DISTRO_USER" -c "bash '$inner'"; then
    rm -f "$inner"
    say "done. open a new shell to pick up the applied environment."
    exit 0
fi

rm -f "$inner"
retry_hint
exit 0
