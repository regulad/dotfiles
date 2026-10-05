#!/bin/bash -e

# =+= START CONFIGURATION =+=
FEDORA_MINIMUM_VERSION=44
MACOS_MINIMUM_VERSION=10.15  # Catalina. tested on 14 and 26; older hosts get era-pinned brew (see .chezmoidata/brew-tiers.toml)
UBUNTU_MINIMUM_VERSION=26.04
# =+= END CONFIGURATION =+=

# Shared preamble included by every .chezmoiscripts/00-{linux,macos}/run_*
# script via `{{ "{{" }} template "posix-preamble.sh" . {{ "}}" }}`. Guards against
# unsupported platforms, loads Homebrew if it is present, and picks a system
# package manager.
# Exports: CONTAINERIZED, IS_WSL, IS_ATOMIC, HAS_BREW, MANAGER, BREW_SECONDARY.
# Defines: can_sudo, require_sudo, load_brew, require_brew, brew_trust.
#
# Two things are deliberately NOT done here:
#
#  - Sudo is not captured. It is acquired lazily by can_sudo, so the scripts
#    which never run a privileged command never trigger a password prompt.
#  - Brew is not installed. That is the job of the 005-homebrew hookscript,
#    which runs before anything that needs brew. A script whose whole job is
#    brew work includes posix-preamble-brew.sh instead of this file: that is
#    this preamble plus `require_brew`, the brew analogue of require_sudo,
#    which fails fast when brew is missing and exports HOMEBREW_PREFIX and the
#    era-pin environment for the rest of the script.
# https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/
#
# Rosetta brew. On an Apple Silicon Mac up to Tahoe 26, a second, x86_64
# Homebrew lives in /usr/local (docs/rosetta-brew.md). Its hookscripts
# (00-macos/006, 021, 031) render the same shared templates as the native
# ones, with brewArch=amd64 added to the template data; everything below that
# depends on the arch reads $brewArch instead of .chezmoi.arch. Such a script
# re-executes itself under Rosetta first, so that uname -m, brew and every
# formula it runs are x86_64 -- brew refuses a /usr/local prefix from a
# native process -- and drops the native brew from the environment it
# inherited from chezmoi.
{{- $brewArch := get . "brewArch" | default .chezmoi.arch }}
{{- $brewSecondary := and (eq .chezmoi.os "darwin") (eq .chezmoi.arch "arm64") (eq $brewArch "amd64") }}
{{- if $brewSecondary }}
if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" != 1 ]; then
	if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
		echo "error: Rosetta 2 is not installed (003-macos-prereqs installs it)" >&2
		exit 1
	fi
	# `bash file` ignores the shebang, so -e is passed explicitly.
	exec /usr/bin/arch -x86_64 /bin/bash -e "$0" "$@"
fi
# Translated from here on. chezmoi was started from a native shell, so PATH
# leads with the native prefix and HOMEBREW_* describe the native brew.
_native_free_path=
_old_ifs="$IFS"
IFS=:
for _d in $PATH; do
	case "$_d" in
		{{ .homebrewPrefix }}|{{ .homebrewPrefix }}/*) ;;
		*) _native_free_path="${_native_free_path:+$_native_free_path:}$_d" ;;
	esac
done
IFS="$_old_ifs"
export PATH="/usr/local/bin:/usr/local/sbin:$_native_free_path"
unset _d _old_ifs _native_free_path HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY
{{- else if eq .chezmoi.os "darwin" }}
#
# Native hookscripts must not run translated: an x86_64 chezmoi (one started
# from an `intel` shell) would render every template for the wrong arch.
# .chezmoiignore.tmpl refuses that case before anything is written; this is
# the backstop for a script run by hand.
if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = 1 ]; then
	echo "error: running under Rosetta; run chezmoi from a native (arm) shell -- \`arm\`" >&2
	exit 1
fi
{{- end }}

echo "debug: entering hookscript" >&2
export DEBIAN_FRONTEND=noninteractive
# HOMEBREW_NO_REQUIRE_TAP_TRUST=1 used to be exported here; brew deprecated
# it. Scripts that touch a non-official tap now `brew trust` what they need
# right before using it (030-brew-extras, 00-macos/040-macos-casks).
export HOMEBREW_NO_ENV_HINTS=1
# brew now defaults to "ask mode" on install/upgrade/reinstall: it prints the
# plan and, when stdin is a TTY and the plan includes anything beyond the named
# packages (i.e. any dependency at all), stops on
#   ==> Do you want to proceed with the installation? [y/n]
# .commonprofile exports this too, but a hookscript only inherits that from a
# shell that has already sourced the *new* profile -- on a first apply, or from
# a terminal opened before the profile changed, it hasn't. Set it here so the
# scripts never depend on the login shell for it.
export HOMEBREW_NO_ASK=1
# `brew services` picks launchd's user/<uid> domain instead of gui/<uid> when
# the apply runs over ssh and nobody is logged in at the Mac's console (it
# checks /dev/console ownership), and warns about it. Every service this repo
# starts is headless, so user/ is fine; brew probes both domains on later
# stop/restart/status anyway. Just drop the noise.
export HOMEBREW_SERVICES_NO_DOMAIN_WARNING=1
trap 'echo "error: line $LINENO: Command was: $BASH_COMMAND" >&2' ERR

# needed for Android native builds. `uname -o` is the one place it is
# needed (Android is only distinguishable there); BSD uname lacks -o before
# macOS 13, hence the silenced error -- everywhere else use `uname -s`.
if [ "$(uname -o 2>/dev/null)" = "Android" ]; then
  export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || true)"
fi

# Panic if running as root or on non-Unix platform
if [[ "$EUID" -eq 0 ]] || [[ "$UID" -eq 0 ]]; then
	echo "error: this script must not be run as root or with sudo" >&2
	exit 1
fi

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
	echo "error: this script does not support Windows/MINGW64/Cygwin environments" >&2
	exit 1
fi

# Whether we can sudo is answered lazily, on first use, and cached for the rest
# of the script.
#
# This used to be an unconditional `sudo -l` right here. Every script includes
# this preamble and every script is its own process, so that probe ran once per
# script -- and `sudo -l` prompts for a password whenever the sudoers timestamp
# has expired or isn't shared with this tty. The result was an apply that asked
# for a password on behalf of the many scripts that never run a single
# privileged command: the go, rust, js and python tooling, brew and its extras,
# the casks, vencord, the user services, the client cert.
#
# So: call can_sudo from the branch that is about to use sudo, and only once the
# privileged work is known to be necessary. Nothing above this line may use it.
can_sudo() {
	if [ -z "$_CAN_SUDO" ]; then
		if sudo -l &>/dev/null; then
			_CAN_SUDO=true
			echo "debug: successfully captured sudo, will use it" >&2
		else
			_CAN_SUDO=false
			echo "warning: can't sudo, will not attempt things that need it" >&2
		fi
	fi
	[ "$_CAN_SUDO" = true ]
}
_CAN_SUDO=

# For scripts whose entire job is privileged -- installing system packages --
# there is no degraded mode worth running, so say so and stop.
require_sudo() {
	if ! can_sudo; then
		echo "error: ${1:-this script} requires sudo but it isn't available" >&2
		exit 1
	fi
}

# NOTE: WSL must be tested BEFORE systemd-detect-virt, not after. systemd
# classifies WSL as a container: `systemd-detect-virt --container` prints "wsl"
# and exits 0 inside a genuine WSL2 distro, so checking it first silently
# marked every WSL session CONTAINERIZED=1 and skipped all of the user-service
# setup that keys off it. (It also prints "wsl" inside a Docker container on a
# WSL2-backed host, which is why WSL_DISTRO_NAME -- set only by WSL's own
# session bootstrap -- is the one signal that actually separates the two.)
if [[ "$OSTYPE" == "darwin"* ]]; then
	CONTAINERIZED=0
	IS_WSL=0
elif [ -n "${WSL_DISTRO_NAME:-}" ]; then
	CONTAINERIZED=0
	IS_WSL=1
elif systemd-detect-virt --container &>/dev/null; then
	CONTAINERIZED=1
	IS_WSL=0
else
	CONTAINERIZED=0
	IS_WSL=0
fi

# Atomic/image-based hosts: Fedora Silverblue and its Universal Blue
# derivatives (Bluefin, Aurora, Bazzite). /run/ostree-booted is created by
# ostree-prepare-root during boot and is the canonical signal. Probing for the
# rpm-ostree binary is NOT equivalent -- a package-mode Fedora can have it
# installed without being booted from an ostree deployment.
if [ -f /run/ostree-booted ]; then
	IS_ATOMIC=1
else
	IS_ATOMIC=0
fi

# START CLAUDE (Claude Sonnet 4.5)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=${VERSION_ID:-0}
elif [ "$(uname)" = "Darwin" ]; then
    OS="macos"
    # The release as Homebrew names it: "11".."27", or "10.15" -- the
    # major alone cannot tell Catalina from the 10.x releases before it.
    VERSION_ID=$(sw_vers -productVersion | cut -d. -f1)
    if [ "$VERSION_ID" = "10" ]; then
        VERSION_ID=$(sw_vers -productVersion | cut -d. -f1-2)
    fi
else
    echo "Error: Unable to detect operating system"
    exit 1
fi
case "$OS" in
    fedora)
        REQUIRED="$FEDORA_MINIMUM_VERSION"
        if [ "$VERSION_ID" -lt "$REQUIRED" ]; then
            echo "Error: Fedora $REQUIRED or higher required (found $VERSION_ID)"
            exit 1
        fi
        ;;
    bluefin)
        # Universal Blue rewrites ID in /usr/lib/os-release at build time
        # (ID=bluefin, ID_LIKE="fedora") but leaves VERSION_ID alone, so it is
        # still the Fedora major the image was built from and the Fedora floor
        # applies unchanged.
        #
        # NOTE: this deliberately rejects Bluefin LTS, which is CentOS Stream
        # based and reports VERSION_ID=10. Nothing in this repo is CentOS
        # tested, and 022-brew-packages.sh assumes the Fedora-derived image's
        # package set when it decides what to leave to the host.
        REQUIRED="$FEDORA_MINIMUM_VERSION"
        if [ "$VERSION_ID" -lt "$REQUIRED" ]; then
            echo "Error: Bluefin built on Fedora $REQUIRED or higher required (found $VERSION_ID)"
            exit 1
        fi
        # Only the -dx images are supported. Universal Blue stamps the image
        # flavour into IMAGE_ID (bluefin-dx, bluefin-dx-nvidia-open, ...);
        # the plain images lack the developer package set that
        # 022-brew-packages.sh and 030-brew-extras.sh assume is in /usr
        # when they decide what to leave to the host (and what to unlink).
        case "${IMAGE_ID:-${VARIANT_ID:-}}" in
            *-dx|*-dx-*) ;;
            *)
                echo "Error: Bluefin -dx image required (found IMAGE_ID=${IMAGE_ID:-unset})"
                echo "notice: rebase with: sudo bootc switch ghcr.io/ublue-os/bluefin-dx:stable"
                exit 1
                ;;
        esac
        ;;
    macos)
        REQUIRED="$MACOS_MINIMUM_VERSION"
        # Numeric major.minor compare in bash: 10.14 < 10.15 < 11 < 26.
        # (Not `sort -V`: BSD sort's support for it varies by macOS release.)
        macos_version_ge() {
            local a_major="${1%%.*}" a_minor="${1#*.}" b_major="${2%%.*}" b_minor="${2#*.}"
            [ "$a_minor" = "$1" ] && a_minor=0
            [ "$b_minor" = "$2" ] && b_minor=0
            [ "$a_major" -gt "$b_major" ] || { [ "$a_major" -eq "$b_major" ] && [ "$a_minor" -ge "$b_minor" ]; }
        }
        if ! macos_version_ge "$VERSION_ID" "$REQUIRED"; then
            echo "Error: macOS $REQUIRED or higher required (found $VERSION_ID)"
            exit 1
        fi
        ;;
    ubuntu)
        REQUIRED="$UBUNTU_MINIMUM_VERSION"
        if [ "$(echo -e "$VERSION_ID\n$REQUIRED" | sort -V | head -n1)" != "$REQUIRED" ]; then
            echo "Error: Ubuntu $REQUIRED or higher required (found $VERSION_ID)"
            exit 1
        fi
        ;;
    *)
        echo "Error: Unsupported operating system: $OS"
        exit 1
        ;;
esac
# END CLAUDE

# =+= Homebrew =+=
#
# The prefix chezmoi decided on at init time (see .chezmoi.toml.tmpl). It is
# the arch rule -- /opt/homebrew on Apple Silicon, /usr/local on Intel,
# /home/linuxbrew/.linuxbrew on Linux. Static config files render the same
# value, so what the hookscripts install against and what tmux/gpg/pam point
# at can never disagree. The Rosetta brew's scripts (BREW_SECONDARY=1) work on
# /usr/local instead, which is Homebrew's own rule for an x86_64 brew.
{{- if $brewSecondary }}
CHEZMOI_HOMEBREW_PREFIX="/usr/local"
BREW_SECONDARY=1
{{- else }}
CHEZMOI_HOMEBREW_PREFIX="{{ .homebrewPrefix }}"
BREW_SECONDARY=0
{{- end }}

# Era pin. A macOS release that mainline Homebrew no longer ships bottles for
# is served by a pinned brew (a release tag) + homebrew/core + homebrew/cask
# (one commit per tap per era, the newest at which every listed formula still
# has this host's bottle; the bottles themselves are still on ghcr.io). The
# table is .chezmoidata/brew-tiers.toml; the 005-homebrew hookscript lays
# brew down by hand and does the checkouts; every brew invocation afterwards
# must carry these two variables or brew will `brew update` itself back to a
# HEAD that doesn't know this OS, and/or read formulae from the JSON API,
# which only describes current bottles. What follows them (brew-era-env.sh)
# makes brew download through its own curl on the releases whose Apple trust
# store is too old for today's download hosts. .commonprofile exports the
# same set for interactive shells.
{{- $brewPin := dict }}
{{- if eq .chezmoi.os "darwin" }}
{{-   $brewPin = index .brewTiers.legacy (printf "%s-%s" .macos.series $brewArch) | default dict }}
{{- end }}
{{- $era := dict }}
{{- if $brewPin }}
{{-   $era = index .brewTiers.eras $brewPin.era }}
BREW_ERA_PINNED=1
BREW_ERA_NAME="{{ $brewPin.era }}"
BREW_PIN_TAG="{{ $brewPin.brew_tag }}"
BREW_ERA_CORE_COMMIT="{{ $era.core_commit }}"
BREW_ERA_CASK_COMMIT="{{ $era.cask_commit }}"
BREW_ERA_SERVICES_COMMIT="{{ index $era "services_commit" | default "" }}"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_FROM_API=1
{{ template "brew-era-env.sh" (dict "era" $brewPin.era) }}
{{- else }}
BREW_ERA_PINNED=0
BREW_ERA_NAME=
BREW_PIN_TAG=
BREW_ERA_CORE_COMMIT=
BREW_ERA_CASK_COMMIT=
BREW_ERA_SERVICES_COMMIT=
{{- end }}

# Every host, pinned or not, Linux included. Set before load_brew, so that
# even the first brew invocation (which may fetch portable-ruby) uses it.
{{ template "brew-mirror-env.sh" .brewMirror }}

# The package lists adapt themselves to the era: each of 020-brew-packages,
# 030-brew-extras and 040-macos-casks resolves the era name the same way
# this file does and, inline next to the entry, uses the name a package had
# at that checkout or leaves out one that did not exist yet or that the host
# cannot satisfy. See the comments in .chezmoidata/brew-tiers.toml.

# Try to load homebrew if it is installed.
#
# Loading an already-installed brew needs no privileges whatsoever, so none of
# these branches consults can_sudo. The sudo test that used to gate the three
# rootful ones was the single biggest reason an apply asked for a password in
# every script: on any machine that has brew -- i.e. all of them -- the first
# branch was reached, and reaching it meant probing sudo.
#
# Probing for the brew binary rather than its prefix directory is also the more
# honest check: a prefix survives a half-finished uninstall, and /usr/local
# exists on practically every Intel Mac whether or not brew is under it.
# The chezmoi-decided prefix is tried first; the rest are fallbacks for a host
# whose brew moved since the last `chezmoi init`. Two exceptions, both because
# Apple Silicon can carry the Rosetta brew in /usr/local: its own scripts
# (BREW_SECONDARY=1) load that brew or none, and native scripts there never
# fall back to it -- a missing /opt/homebrew must not quietly turn into
# installing native packages into the x86_64 prefix.
load_brew() {
	local candidate candidates
	if [ "$BREW_SECONDARY" -eq 1 ]; then
		candidates="$CHEZMOI_HOMEBREW_PREFIX/bin/brew"
	elif [ "$(uname -s)" = "Darwin" ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
		candidates="$CHEZMOI_HOMEBREW_PREFIX/bin/brew /opt/homebrew/bin/brew"
	else
		candidates="$CHEZMOI_HOMEBREW_PREFIX/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew"
	fi
	for candidate in $candidates; do
		[ -x "$candidate" ] || continue
		eval "$("$candidate" shellenv)"
		return 0
	done
	return 1
}

# For scripts whose entire job is brew work. The brew analogue of
# require_sudo: there is no degraded mode worth running without it, so say so
# and stop. Also the one place that guarantees HOMEBREW_PREFIX is set (brew
# shellenv exports it) -- scripts that include posix-preamble-brew.sh may use
# $HOMEBREW_PREFIX freely; scripts on the plain preamble may not.
require_brew() {
	if ! load_brew; then
		echo "error: ${1:-this script} requires brew but it isn't installed (expected under $CHEZMOI_HOMEBREW_PREFIX; 005-homebrew installs it)" >&2
		exit 1
	fi
	if [ -z "${HOMEBREW_PREFIX:-}" ]; then
		echo "error: brew shellenv did not export HOMEBREW_PREFIX" >&2
		exit 1
	fi
	# The repo is the prefix itself on Apple Silicon but $prefix/Homebrew on
	# Intel and Linux; located without asking brew, which on a 10.x host would
	# refuse to start if the pin had been lost.
	local brew_repo="$HOMEBREW_PREFIX"
	[ -d "$HOMEBREW_PREFIX/Homebrew/.git" ] && brew_repo="$HOMEBREW_PREFIX/Homebrew"
	if [ "$BREW_ERA_PINNED" -eq 1 ] && [ "$(git -C "$brew_repo" describe --tags --exact-match 2>/dev/null)" != "$BREW_PIN_TAG" ]; then
		echo "warning: brew at $HOMEBREW_PREFIX is not at pinned tag $BREW_PIN_TAG; re-run 005-homebrew (chezmoi apply --force)" >&2
	fi
}

# `brew trust` (tap/formula trust, 2026) does not exist in an era-pinned brew,
# and an old brew never demanded it. Scripts call this instead of `brew trust`
# so the same list works on both.
brew_trust() {
	if [ -z "${_BREW_HAS_TRUST:-}" ]; then
		if brew commands --quiet 2>/dev/null | grep -qx trust; then
			_BREW_HAS_TRUST=1
		else
			_BREW_HAS_TRUST=0
		fi
	fi
	if [ "$_BREW_HAS_TRUST" -eq 1 ]; then
		brew trust "$@"
	fi
}
_BREW_HAS_TRUST=

load_brew || true

# every split script runs as its own process, so re-derive PATH/env that earlier
# scripts (e.g. rustup, go) would have set up rather than assuming it carried over
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
# brew's rustup formula (00-macos/020) is keg-only, so its rustup and the
# cargo/rustc proxies stay in the keg; .commonprofile adds the same dir.
[ -n "${HOMEBREW_PREFIX:-}" ] && [ -d "$HOMEBREW_PREFIX/opt/rustup/bin" ] && export PATH="$HOMEBREW_PREFIX/opt/rustup/bin:$PATH"
# MacPorts (00-macos/016), ahead of brew as in .commonprofile.
[ -d /opt/local/bin ] && export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

command -v brew &>/dev/null && HAS_BREW=true || HAS_BREW=false

if [ "$IS_ATOMIC" -eq 1 ]; then
	# /usr belongs to the bootc image and is mounted read-only, so no system
	# package manager can install into it; brew (in /var/home/linuxbrew) is the
	# supported route, and 022-brew-packages.sh is the runner that uses it.
	#
	# This has to be tested BEFORE the dnf branch, not after it: these images
	# still carry /etc/redhat-release, and dnf may be on PATH, so the dnf
	# branch would win and then fail mid-transaction on a read-only /usr.
	MANAGER="brew"
elif command -v dnf &>/dev/null && [[ -f /etc/redhat-release ]]; then
	MANAGER="dnf"
elif command -v apt &>/dev/null && [[ -f /etc/debian_version ]]; then
	MANAGER="apt"
elif [[ "$OSTYPE" == "darwin"* ]]; then
	# brew is the manager on macOS whether or not it is installed yet: the
	# 005-homebrew hookscript itself includes this preamble, and it has to
	# get past this point to do the installing. Scripts that need brew to
	# exist say so with require_brew.
	MANAGER="brew"
	# The macOS one-offs that used to sit here are 00-macos/003-macos-prereqs
	# (Xcode CLT, Rosetta) and 015-brew-taps (third-party taps) now: every
	# hookscript includes this preamble as its own process, so they ran ~20x
	# per apply.
else
	MANAGER=""
fi

# NOTE: the "dnf/apt need sudo, bail out if we haven't got it" check used to sit
# here. Being here is what made it a problem: MANAGER is dnf or apt on every
# Fedora and Ubuntu box, so the check fired -- and probed sudo -- in all 26
# scripts that include this preamble, not just the two that hand work to the
# package manager. It now lives in those two, as `require_sudo`.

# Check if any manager was detected
if [[ -z "$MANAGER" ]]; then
	echo "warning: no package manager detected" >&2
  exit 1
fi
