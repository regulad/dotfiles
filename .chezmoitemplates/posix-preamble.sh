#!/bin/bash -e

# =+= START CONFIGURATION =+=
FEDORA_MINIMUM_VERSION=44
MACOS_MINIMUM_VERSION=14  # tested on 14 and 26
UBUNTU_MINIMUM_VERSION=26.04
# =+= END CONFIGURATION =+=

# Shared preamble included by every .chezmoiscripts/00-posix/run_after_* script
# via `{{ "{{" }} template "posix-preamble.sh" . {{ "}}" }}`. Guards against unsupported
# platforms, loads/installs Homebrew, and picks a system package manager.
# Exports: CONTAINERIZED, IS_WSL, IS_ATOMIC, HAS_BREW, MANAGER.
# Defines: can_sudo, require_sudo, load_brew.
#
# Sudo is NOT captured here -- it is acquired lazily by can_sudo, so that the
# scripts which never run a privileged command never trigger a password prompt.
# https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/

echo "note: entering hookscript" >&2
export DEBIAN_FRONTEND=noninteractive
export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
export HOMEBREW_NO_ENV_HINTS=1
trap 'echo "error: line $LINENO: Command was: $BASH_COMMAND" >&2' ERR

# needed for Android native builds
if [ "$(uname -o)" = "Android" ]; then
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
			echo "note: successfully captured sudo, will use it" >&2
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
    VERSION_ID=$(sw_vers -productVersion | cut -d. -f1)
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
        ;;
    macos)
        REQUIRED="$MACOS_MINIMUM_VERSION"
        if [ "$VERSION_ID" -lt "$REQUIRED" ]; then
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
load_brew() {
	local candidate
	for candidate in \
		/opt/homebrew/bin/brew \
		/usr/local/bin/brew \
		/home/linuxbrew/.linuxbrew/bin/brew \
		"$HOME/homebrew/bin/brew"; do
		[ -x "$candidate" ] || continue
		if [ "$candidate" = "$HOME/homebrew/bin/brew" ]; then
			echo "warning: loading rootless brew. this often works but is unsupported." >&2
		fi
		eval "$("$candidate" shellenv)"
		return 0
	done
	return 1
}

load_brew || true

# brew is a nother binary dependency but ONLY on linux for addl. userspace packages
# don't think any of the addl. userpsace packages need to be installed by this script
if ! command -v brew &>/dev/null && [[ "$(uname -o)" == "Darwin" || "$(uname -o)" == "GNU/Linux" ]]; then
	echo "note: installing brew" >&2
	# One of the few places that legitimately asks: the official installer puts
	# brew under /opt/homebrew or /home/linuxbrew, both of which need root to
	# create. Only reached when brew is genuinely absent.
	if can_sudo; then
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		if [ "$(uname -o)" = "Darwin" ] && [ "$(arch)" = "arm64" ]; then
			sudo launchctl config user path /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
			sudo launchctl config system path /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
		elif [ "$(uname -o)" = "Darwin" ] && [ "$(arch)" = "x86_64" ]; then
			sudo launchctl config user path /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
			sudo launchctl config system path /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
		fi
	else
		echo "warning: can't do default brew install w/o sudo; installing rootlessly" >&2
		# Explicitly $HOME/homebrew: this used to be a bare `mkdir homebrew`,
		# which lands wherever the apply happens to be running from, while
		# every detection branch looks under $HOME. They coincide only because
		# chezmoi usually runs scripts from the destination dir.
		mkdir -p "$HOME/homebrew" && curl -L https://github.com/Homebrew/brew/tarball/main | tar xz --strip-components 1 -C "$HOME/homebrew"

		eval "$("$HOME/homebrew/bin/brew" shellenv)"
		brew update --force --quiet
		chmod -R go-w "$(brew --prefix)/share/zsh"
	fi

	# After Homebrew installation, detect and load it
	load_brew || true
fi

# every split script runs as its own process, so re-derive PATH/env that earlier
# scripts (e.g. rustup, go) would have set up rather than assuming it carried over
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

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
elif command -v brew &>/dev/null && [[ "$OSTYPE" == "darwin"* ]]; then
	MANAGER="brew"

	# macOS brew-specific tap / dep setups
	brew tap kde-mac/kde https://invent.kde.org/packaging/homebrew-kde.git && "$(brew --repo kde-mac/kde)/tools/do-caveats.sh"
	brew tap regulad/homebrew-tap
	brew tap Gcenx/wine https://github.com/Gcenx/homebrew-wine

	# software updates
	if [ "$(arch)" = "arm64" ]; then
		# despite being an sbin, this is usable by non-root users. til
		/usr/sbin/softwareupdate --install-rosetta --agree-to-license
	fi
	xcode-select --install || true  # returns exit code 1 when tools are already installed
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
