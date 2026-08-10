#!/bin/bash -e

# =+= START CONFIGURATION =+=
FEDORA_MINIMUM_VERSION=44
MACOS_MINIMUM_VERSION=14  # tested on 14 and 26
UBUNTU_MINIMUM_VERSION=26.04
# =+= END CONFIGURATION =+=

# Shared preamble included by every .chezmoiscripts/00-posix/run_after_* script
# via `{{ "{{" }} template "posix-preamble.sh" . {{ "}}" }}`. Guards against unsupported
# platforms, captures sudo, loads/installs Homebrew, and picks a system package
# manager. Exports: CAN_SUDO, CONTAINERIZED, IS_WSL, HAS_BREW, MANAGER.
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

# TODO: fix the ai slop =true and =false and replace it with a real bash =0 and =1
if ! sudo -l &>/dev/null; then
	echo "warning: Can't sudo. Will not attempt to install things that need sudo." >&2
	CAN_SUDO=false
else
	echo "note: Successfully captured sudo. Will use it." >&2
	CAN_SUDO=true
fi

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

# Try to load homebrew if it is installed
if [[ -d "/opt/homebrew" && "$CAN_SUDO" = "true" ]]; then
	# Apple Silicon Mac (rootful)
	eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ (-d "/usr/local/Homebrew" || -d "/usr/local/bin/brew") && "$CAN_SUDO" = "true" ]]; then
	# Intel Mac (rootful)
	eval "$(/usr/local/bin/brew shellenv)"
elif [[ -d "/home/linuxbrew/.linuxbrew" && "$CAN_SUDO" = "true" ]]; then
	# Linux
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -d "$HOME/homebrew" ]]; then
	# Rootless homebrew (macOS & Linux)
	echo "warning: loading rootless brew. this often works but is unsupported." >&2
	eval "$("$HOME/homebrew/bin/brew" shellenv)"
fi

# brew is a nother binary dependency but ONLY on linux for addl. userspace packages
# don't think any of the addl. userpsace packages need to be installed by this script
if ! command -v brew &>/dev/null && [[ "$(uname -o)" == "Darwin" || "$(uname -o)" == "GNU/Linux" ]]; then
	echo "note: installing brew" >&2
	if [ "$CAN_SUDO" = "true" ]; then
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
		mkdir homebrew && curl -L https://github.com/Homebrew/brew/tarball/main | tar xz --strip-components 1 -C homebrew

		eval "$(homebrew/bin/brew shellenv)"
		brew update --force --quiet
		chmod -R go-w "$(brew --prefix)/share/zsh"
	fi

	# After Homebrew installation, detect and load it
	if [[ -d "/opt/homebrew" && "$CAN_SUDO" = "true" ]]; then
		# Apple Silicon Mac (rootful)
		eval "$(/opt/homebrew/bin/brew shellenv)"
	elif [[ (-d "/usr/local/Homebrew" || -d "/usr/local/bin/brew") && "$CAN_SUDO" = "true" ]]; then
		# Intel Mac (rootful)
		eval "$(/usr/local/bin/brew shellenv)"
	elif [[ -d "/home/linuxbrew/.linuxbrew" && "$CAN_SUDO" = "true" ]]; then
		# Linux
		eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
	elif [[ -d "$HOME/homebrew" ]]; then
		# Rootless homebrew (macOS & Linux)
		eval "$(homebrew/bin/brew shellenv)"
	fi
fi

# every split script runs as its own process, so re-derive PATH/env that earlier
# scripts (e.g. rustup, go) would have set up rather than assuming it carried over
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

command -v brew &>/dev/null && HAS_BREW=true || HAS_BREW=false

if command -v dnf &>/dev/null && [[ -f /etc/redhat-release ]]; then
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

# Check sudo requirement for dnf5 and apt
if [[ "$MANAGER" == "dnf" || "$MANAGER" == "apt" ]] && ! [ "$CAN_SUDO" = "true" ]; then
	echo "warning: package manager needs sudo but it isn't available" >&2
  exit 1
fi

# Check if any manager was detected
if [[ -z "$MANAGER" ]]; then
	echo "warning: no package manager detected" >&2
  exit 1
fi
