#!/bin/bash -e

# Installs neccesary tools to enable everything from the dotfiles
# https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/
# NOTE!! this is ONLY for true nix. no MINGW64; will handle that separately.
# yes, i realize how dumb that this is when I could just use nix. lol.

echo "note: entering hookscript" >&2

# Panic if running as root or on non-Unix platform
if [[ "$EUID" -eq 0 ]] || [[ "$UID" -eq 0 ]]; then
    echo "error: this script must not be run as root or with sudo" >&2
    exit 1
fi

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo "error: this script does not support Windows/MINGW64/Cygwin environments" >&2
    exit 1
fi

if ! sudo -l &>/dev/null; then
    echo "warning: Can't sudo. Will not attempt to install things that need sudo." >&2
    CAN_SUDO=0
else
    echo "note: Successfully captured sudo. Will use it." >&2
    CAN_SUDO=1
fi

# brew is a nother binary dependency but ONLY on linux for addl. userspace packages
# don't think any of the addl. userpsace packages need to be installed by this script
if ! command -v brew &> /dev/null && [[ "$(uname -o)" == "Darwin" || "$(uname -o)" == "GNU/Linux" ]]; then
    echo "note: installing brew" >&2
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# After Homebrew installation, detect and load it
if [ -d "/opt/homebrew" ]; then
    # Apple Silicon Mac
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -d "/usr/local/Homebrew" ] || [ -d "/usr/local/bin/brew" ]; then
    # Intel Mac
    eval "$(/usr/local/bin/brew shellenv)"
elif [ -d "/home/linuxbrew/.linuxbrew" ]; then
    # Linux
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# system-level binary dependencies
#     - these are typically very stable applications that MUST be provided by a package manager
#     - they are not particularly version-sensitive; pinning is unnecesary
#     - they are all f(l)oss
# package managers:
#     - brew (macos) [m:]
#     - apt (debian) [d:]
#     - dnf (redhat) [r:]
#     - pkg (termux) [t:]
PRIMARY_BINARY_DEPENDENCIES=(
    # =+= CORE
    "drt:build-essential"
    #"mdrt:bash"
    "mdrt:zsh"
    
    # =+= EDITOR
    "mdrt:neovim"  # nvim
    #"mdrt:vim"
    
    # =+= UTILS
    "mdrt:git"
    "mdrt:git-lfs"
    "mdt:gnupg"  # gpg
    "r:gnupg2"
    "mdrt:openssh"  # ssh-agent & ssh 
    "mdrt:keychain"
    "mdrt:gh"  # GitHub
    "mdrt:restic"
    "mdrt:ffmpeg"

    # =+= JS/TS
    "m:node"
    "dr:nodejs"
    "t:nodejs-lts"
    "mdr:npm"  # just to install pnpm; part of nodejs-lts on termux
    
    # =+= JVM
    "m:openjdk"
    "r:java-latest-openjdk"
    "d:default-jdk"
    "t:openjdk-25"  # NOTE: remember to update to latest LTS
    "mdrt:maven"

    # =+= RUST
    "md:rustup"
    "r:cargo"  # part of rust on termux
    "r:rustfmt"  # also part of rust on termux
    "rt:rust"
    "rt:rust-analyzer"

    # =+= PYTHON (>= 3.12)
    "mdr:python3"  # NOTE: only >= 3.12 on RHEL >= 10 (fedora ???)
    "dr:python3-pip"
    "d:python3-venv"
    "t:python"
)

if command -v pkg &> /dev/null && [[ "$PREFIX" == *"com.termux"* ]]; then
    MANAGER="pkg"
elif command -v dnf5 &> /dev/null && [[ -f /etc/redhat-release ]]; then
    MANAGER="dnf5"
elif command -v apt &> /dev/null && [[ -f /etc/debian_version ]]; then
    MANAGER="apt"
elif command -v brew &> /dev/null && [[ "$OSTYPE" == "darwin"* ]]; then
    MANAGER="brew"
else
    MANAGER=""
fi

# Check sudo requirement for dnf5 and apt
if [[ "$MANAGER" == "dnf5" || "$MANAGER" == "apt" ]] && [[ "$CAN_SUDO" -ne 1 ]]; then
    echo "warning: package manager needs sudo but it isn't available" >&2
    MANAGER=""
fi

# Check if any manager was detected
if [[ -z "$MANAGER" ]]; then
    echo "warning: no package manager detected" >&2
fi

# Filter dependencies based on package manager
if [[ -n "$MANAGER" ]]; then
    TO_INSTALL=()
    for dep in "${PRIMARY_BINARY_DEPENDENCIES[@]}"; do
        # Extract prefix and package name
        prefix="${dep%%:*}"
        package="${dep#*:}"
        
        # Check if this package applies to current manager
        case "$MANAGER" in
            pkg)
                [[ -z "$prefix" || "$prefix" == *"t"* ]] && TO_INSTALL+=("$package")
                ;;
            dnf5)
                [[ -z "$prefix" || "$prefix" == *"r"* ]] && TO_INSTALL+=("$package")
                ;;
            apt)
                [[ -z "$prefix" || "$prefix" == *"d"* ]] && TO_INSTALL+=("$package")
                ;;
            brew)
                [[ -z "$prefix" || "$prefix" == *"m"* ]] && TO_INSTALL+=("$package")
                ;;
        esac
    done
    
    # Install packages if any were found
    if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
        case "$MANAGER" in
            pkg)
                pkg install -y "${TO_INSTALL[@]}"
                ;;
            dnf5)
                sudo dnf5 install -y "${TO_INSTALL[@]}"
                ;;
            apt)
                sudo apt update
                sudo apt install -y "${TO_INSTALL[@]}"
                ;;
            brew)
                brew install "${TO_INSTALL[@]}"
                ;;
        esac
    fi
fi

# Setup Rust toolchain if needed
if command -v rustup-init &> /dev/null && [[ ! -d "$HOME/.cargo" ]]; then
    rustup-init -y --default-toolchain stable --profile default
    source "$HOME/.cargo/env"
    rustup component add rust-analyzer
elif command -v rustup &> /dev/null; then
    if ! rustup toolchain list 2>/dev/null | grep -q .; then
        rustup set profile default
        rustup toolchain install stable
        rustup component add rust-analyzer
    fi
fi

# user-level binary dependencies
# these dependencies aren't provided by the system package manager, for whatever reason
# these packages do NOT require compilation and are distributed as binaries. 
# they may be closed-source/non-libre (although I don't think any are).
# brew distributes a lot of these as formulae.
# most of them are needed for specific workflows (i.e. kotlin, python, java)
SECONDARY_BINARY_DEPENDENCIES=(
    # =+= Bare
    "wakatime-cli"  # TODO: brew provides; termux can provide; fallback bare binary from https://github.com/wakatime/wakatime-cli
    "kotlin-lsp"  # TODO: brew provides `brew install kotlin-language-server`; else bare binary from https://github.com/Kotlin/kotlin-lsp
    "kotlin"  # TODO: brew provides `brew install kotlin`, debian provides with `kotlin`, termux provides with `kotlin`, else bare https://kotlinlang.org/docs/command-line.html
    "jdtls"  # TODO: brew provides `jldts`, else bare binary from https://download.eclipse.org/jdtls/milestones/1.54.0/repository/

    # =+= PyPi
    "poetry"  # TODO: debian can provide this `apt install -y python3-poetry`, as can brew; fallback pip global

    # =+= npm
    "pnpm"  # TODO: do `npm i -g pnpm` on non-brew
    "bitwarden-cli"  # TODO: do `pnpm install -g @bitwarden/cli` on non-brew
    "pyright"  # TODO: brew provides; else `pnpm i -g pyright`
    "typescript"  # TODO: brew provides; else `pnpm i -g typescript`
    "typescript-language-server"  # TODO: brew provides; else `pnpm i -g typescript-language-server`
)
command -v brew &> /dev/null && HAS_BREW=true || HAS_BREW=false
# TODO: kotlinc and fernflower

# vim package management
# NOTE: because I use neovim in lieu of vim, I'm not going to install Vundle
# lazy doesn't need to be installed itself but it does need some native dependencies

# oh my zsh
if ! [ -d ~/.oh-my-zsh ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# TODO: load custom ca into keychain from ~/.x509/ipa-ca.crt
# TODO: chsh to zsh if not already the shell

echo "note: exiting hookscript. don't buy it if something after this point asks for sudo!" >&2
