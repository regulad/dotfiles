#!/bin/bash -e

# Installs neccesary tools to enable everything from the dotfiles
# https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/
# NOTE!! this is ONLY for true nix. no MINGW64; will handle that separately.
# yes, i realize how dumb that this is when I could just use nix. lol.

echo "note: entering hookscript" >&2
export DEBIAN_FRONTEND=noninteractive

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

# Try to load homebrew if it is installed
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

# brew is a nother binary dependency but ONLY on linux for addl. userspace packages
# don't think any of the addl. userpsace packages need to be installed by this script
if ! command -v brew &> /dev/null && [[ "$(uname -o)" == "Darwin" || "$(uname -o)" == "GNU/Linux" ]]; then
    echo "note: installing brew" >&2
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
fi


export PATH="$PATH:$HOME/.local/bin"

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
    "t:file"
    "t:man"
    
    # =+= EDITOR
    "mdrt:neovim"  # nvim
    #"mdrt:vim"
    
    # =+= UTILS
    "mdrt:git"
    "mdrt:git-lfs"
    "mdt:gnupg"  # gpg
    "r:gnupg2"
    "d:openssh-client"
    "mrt:openssh"  # ssh-agent & ssh 
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
                sudo apt update -qq
                sudo apt install -qq -y "${TO_INSTALL[@]}"
                ;;
            brew)
                brew install -q "${TO_INSTALL[@]}"
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

if [ "$MANAGER" = "brew" ] && [[ "$CAN_SUDO" -ne 1 ]]; then
    sudo ln -sfn $HOMEBREW_PREFIX/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
fi

# user-level binary dependencies
# these dependencies aren't provided by the system package manager, for whatever reason
# these packages do NOT require compilation and are distributed as binaries. 
# they may be closed-source/non-libre (although I don't think any are).
# brew distributes these on GNU/Linux and Darwin. no attempt is made on other platforms
# most of them are needed for specific workflows (i.e. kotlin, python, java)
SECONDARY_BINARY_DEPENDENCIES=(
    "wakatime-cli"
    "kotlin"
    "kotlin-language-server"
    "fernflower"
    "jdtls"
)
command -v brew &> /dev/null && HAS_BREW=true || HAS_BREW=false

if [ "$HAS_BREW" = "true" ]; then
    brew install -q "${SECONDARY_BINARY_DEPENDENCIES[@]}"
else
    echo "warning: no brew for misc. binary deps" >&2
fi

# js/ts
if [ "$HAS_BREW" = "true" ]; then
    brew install -q pnpm
else
    npm i -g -q pnpm@latest
fi

if [ -z "$PNPM_HOME" ]; then
    mv ~/.zshrc ~/.zshrc.pre-pnpm
    SHELL=zsh pnpm setup || true
    rm ~/.zshrc
    mv ~/.zshrc.pre-pnpm ~/.zshrc
fi

PNPM_CLI_PACKAGES=(
    "ezff@latest"
)

if [ "$HAS_BREW" = "true" ]; then
    brew install -q bitwarden-cli pyright typescript typescript-language-server
else
    PNPM_CLI_PACKAGES+=("@bitwarden/cli@latest" "pyright@latest" "typescript@latest" "typescript-language-server@latest")
fi

pnpm i -g --silent "${PNPM_CLI_PACKAGES[@]}"

# Poetry
# NOTE: redhat repositories provide poetry-core but not the CLI
# NOTE: on brew platforms, the --user pip environment is externally handled
if [ "$MANAGER" = "apt" ]; then
    sudo apt install -y python3-poetry
elif [ "$HAS_BREW" = "true" ]; then
    brew install -q poetry
else
    pip install --user -q poetry
fi

# UV
if [ "$HAS_BREW" = "true" ]; then
    brew install -q uv
else
    pip install --user -q uv
fi

# NOTE: poetry is for legacy workflows. 
# NOTE: `uv tool install` replaces pipx
# can install with `pipx i <package>`
# or `uv tool install <package>`
PYPI_CLI_PACKAGES=(
    "yt-dlp"  # NOTE: although this is in the Ubuntu repositories; would be better to update dynamically
)

for cli in "${PYPI_CLI_PACKAGES[@]}"; do
    uv tool install -q ${cli}
done

# vim package management
# NOTE: because I use neovim in lieu of vim, I'm not going to install Vundle
# lazy doesn't need to be installed itself but it does need some native dependencies

# oh my zsh
if ! [ -d ~/.oh-my-zsh ]; then
    mv ~/.zshrc ~/.zshrc.pre-oh-my-zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    rm ~/.zshrc
    mv ~/.zshrc.pre-oh-my-zsh ~/.zshrc
fi

# load zsh as primary shell
ZSH_PATH=$(command -v zsh)

if ! [ "$(uname -o)" = "Android" ]; then 
    # Check if detected zsh is in /etc/shells
    if [ -n "$ZSH_PATH" ] && ! grep -q "^$ZSH_PATH$" /etc/shells; then
        echo "warning: $ZSH_PATH not in /etc/shells, using zsh in /etc/shells if exists" >&2
        ZSH_PATH=$(grep -m1 '/zsh$' /etc/shells)
     fi
    
    # If no zsh in /etc/shells, fall back to bash
    if [ -z "$ZSH_PATH" ]; then
        echo "warning: falling back to bash since zsh isn't available in /etc/shells" >&2
    
        BASH_PATH=$(command -v bash)
        
        if [ -n "$BASH_PATH" ] && ! grep -q "^$BASH_PATH$" /etc/shells; then
            echo "warning: $BASH_PATH not in /etc/shells, using bash in /etc/shells if exists" >&2
            BASH_PATH=$(grep -m1 '/bash$' /etc/shells)
        fi
    
        if [ -z "$BASH_PATH" ]; then
            echo "error: no valid shell found in /etc/shells" >&2
            exit 1
        fi
        
        SHELL_PATH="$BASH_PATH"
    else
        SHELL_PATH="$ZSH_PATH"
    fi
    
    # Change shell if not already set
    if [ "$SHELL" != "$SHELL_PATH" ]; then
        chsh -s "$SHELL_PATH"
        echo "note: shell was changed" >&2
    fi
else
    chsh -s zsh
fi

# final step: upgrade dependencies but ONLY for user-level pms
if [ "$HAS_BREW" = "true" ]; then
   brew upgrade -q
fi
pnpm update --global --silent
uv tool upgrade --quiet --all

# Certificate installation
declare -a CERT_PATHS=()

# this script will run before first apply, so the file won't exist
if [[ -f "$HOME/.chezmoi-did-apply" ]]; then
    CERT_PATHS+=(
        "$HOME/.x509/ipa-ca.crt"
    )
else
    echo "note: running before first apply, using working tree files" >&2
    CERT_PATHS+=(
        "$HOME/.local/share/chezmoi/dot_x509/ipa-ca.crt"
    )
fi

# Detect OS and install certificates
if [[ "$(uname -o)" == "Android" ]]; then
    # Termux/Android
    echo "note: on Android/Termux, certificates must be added manually to the system trust store" >&2
    
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    for CERT_PATH in "${CERT_PATHS[@]}"; do
        # Check if certificate is already trusted
        if ! security verify-cert -c "$CERT_PATH" &>/dev/null; then
            if [ "$CAN_SUDO" -eq 1 ]; then
                sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_PATH"
            else
                security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db "$CERT_PATH"
                echo "warning: added certificate to user keychain only (no sudo available)" >&2
            fi
        fi
    done
    
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if [ "$CAN_SUDO" -eq 1 ]; then
        NEEDS_UPDATE=0
        
        for CERT_PATH in "${CERT_PATHS[@]}"; do
            # Check if certificate is already in system trust store
            if ! openssl verify -CApath /etc/ssl/certs "$CERT_PATH" &>/dev/null; then
                CERT_NAME=$(basename "$CERT_PATH")
                
                if [ -d /etc/pki/ca-trust/source/anchors ]; then
                    # RHEL/CentOS/Fedora
                    sudo cp "$CERT_PATH" "/etc/pki/ca-trust/source/anchors/$CERT_NAME"
                    NEEDS_UPDATE=1
                elif [ -d /usr/local/share/ca-certificates ]; then
                    # Debian/Ubuntu
                    sudo cp "$CERT_PATH" "/usr/local/share/ca-certificates/$CERT_NAME"
                    NEEDS_UPDATE=1
                fi
            fi
        done
        
        # Update trust store only if new certs were added
        if [ "$NEEDS_UPDATE" -eq 1 ]; then
            if [ -d /etc/pki/ca-trust/source/anchors ]; then
                sudo update-ca-trust
            elif [ -d /usr/local/share/ca-certificates ]; then
                sudo update-ca-certificates
            fi
        fi
    else
        echo "warning: sudo required to install system certificate on Linux, skipping" >&2
    fi
fi

echo "note: exiting hookscript. don't buy it if something after this point asks for sudo!" >&2
