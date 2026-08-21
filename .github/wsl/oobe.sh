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
# Credentials: `bw login --apikey` reads BW_CLIENTID and BW_CLIENTSECRET from
# the environment and prompts for them when absent. ~/.secrets/.bwrc exports
# exactly those two variables. It cannot exist yet inside a fresh instance --
# that file is itself templated *out of* Bitwarden (dot_secrets/dot_bwrc.tmpl),
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

if ! getent passwd "$DISTRO_UID" >/dev/null 2>&1; then
    warn "uid $DISTRO_UID is missing from this image, which should be impossible."
    warn "skipping first-run setup."
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

cat > "$inner" <<INNER
#!/bin/bash
set -u

# runuser -l starts a fresh login environment, which drops WSL's own exports.
# WSL_DISTRO_NAME has to survive: .chezmoiignore keys the WSL-only scriptlets
# (004-wsl-binfmt-interop, 006-wsl-gpu, 007-ssh-agent-relay) off it, and the
# posix preamble uses it to tell a real WSL session apart from a container --
# systemd-detect-virt reports "wsl" for both.
export WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-}"

# Path only -- the credentials themselves are never passed through argv or the
# environment of this script, so they never appear in ps for other users.
BWRC="${BWRC}"
if [ -n "\$BWRC" ] && [ -r "\$BWRC" ]; then
    # shellcheck disable=SC1090
    . "\$BWRC"
    if [ -n "\${BW_CLIENTID:-}" ] && [ -n "\${BW_CLIENTSECRET:-}" ]; then
        export BW_CLIENTID BW_CLIENTSECRET
        echo "note: API credentials loaded from \$BWRC" >&2
    else
        echo "warning: \$BWRC did not define BW_CLIENTID/BW_CLIENTSECRET; will prompt" >&2
    fi
fi

bw config server "${BW_SERVER}" || exit 1

if bw login --check >/dev/null 2>&1; then
    echo "note: already logged in to Bitwarden" >&2
else
    bw login --apikey || exit 1
fi

# chezmoi's own [bitwarden] unlock = "auto" handles the vault session for
# templating; this just fails fast with a clear message if the vault will not
# unlock, rather than letting every bitwarden template lookup fail one by one.
if ! bw unlock --check >/dev/null 2>&1; then
    BW_SESSION="\$(bw unlock --raw)" || exit 1
    export BW_SESSION
fi

# Regenerate the config with useDummySecrets = false. The image was built with
# CHEZMOI_USE_DUMMY=1, and that value is baked into chezmoi.toml, not re-derived.
chezmoi init || exit 1

# age identity first -- everything encrypted depends on it.
chezmoi apply "\$HOME/key.txt" || exit 1

# Full apply. Expected to do real work here: encrypted files, real secrets, and
# the WSL-only scriptlets, none of which ran during the image build.
chezmoi apply || exit 1
INNER

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
