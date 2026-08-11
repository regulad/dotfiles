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
# the environment and prompts for them when they are absent. ~/.secrets/.bwrc
# exports exactly those two variables, so it is sourced when present -- but it
# cannot be relied on for a first run, because that file is itself templated
# *out of* Bitwarden (see dot_secrets/dot_bwrc.tmpl) and so does not exist
# until an authenticated apply has already happened. First run prompts; later
# runs pick the file up. Nothing secret is ever baked into the image: both
# ~/.secrets/ and ~/key.txt are masked by useDummySecrets during the build.

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

  You will be asked for your Bitwarden API client id and secret. Get them
  from ${BW_SERVER} under Account Settings -> Security -> Keys ->
  View API Key.

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

# The real work runs as the unprivileged user, in a login shell, via a script
# file rather than `runuser -c '<long string>'` -- quoting a heredoc through
# runuser's -c is a foot-gun, and anything passed on the command line would be
# visible in ps to every other user on the system.
inner="$(mktemp /tmp/oobe-inner.XXXXXX.sh)"
chmod 0700 "$inner"
chown "$DISTRO_USER" "$inner"

cat > "$inner" <<INNER
#!/bin/bash
set -u

# runuser -l starts a fresh login environment, which drops WSL's own exports.
# WSL_DISTRO_NAME has to survive: .chezmoiignore keys the WSL-only scriptlets
# (004-wsl-binfmt-interop, 006-wsl-gpu, 007-ssh-agent-relay) off it, and the
# posix preamble uses it to tell a real WSL session apart from a container --
# systemd-detect-virt reports "wsl" for both.
export WSL_DISTRO_NAME="${WSL_DISTRO_NAME:-}"

if [ -r "\$HOME/.secrets/.bwrc" ]; then
    echo "note: sourcing existing \$HOME/.secrets/.bwrc for API credentials" >&2
    # shellcheck disable=SC1091
    . "\$HOME/.secrets/.bwrc"
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

say "running first-run apply as ${DISTRO_USER} (this will take a few minutes)"

if runuser -l "$DISTRO_USER" -c "bash '$inner'"; then
    rm -f "$inner"
    say "done. open a new shell to pick up the applied environment."
    exit 0
fi

rm -f "$inner"
retry_hint
exit 0
