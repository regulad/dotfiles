#!/bin/bash -e

# Installs neccesary tools to enable everything from the dotfiles
# https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/
# NOTE!! this is ONLY for true nix. no MINGW64; will handle that separately.
# yes, i realize how dumb that this is when I could just use nix. lol.

echo "note: entering hookscript" >&2

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

# system-level binary dependencies
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

# TODO: actual install logic

# TODO: On brew: need to run rustup-init if ~/.cargo doesn't exist and rustup install provides rustup-init (only macOS?)
# TODO: On a system with rustup on first boot with no toolchains installed
# rustup set profile default
#     && rustup toolchain install stable
#     && rustup install stable
#     && rustup component add rust-analyzer

# user-level binary dependencies
# these dependencies aren't provided by the system package manager, for whatever reason
SECONDARY_BINARY_DEPENDENCIES=(
    # =+= Bare
    "wakatime-cli"  # TODO: brew provides; termux can provide; fallback bare binary from https://github.com/wakatime/wakatime-cli
    "kotlin-lsp"  # TODO: brew provides `brew install JetBrains/utils/kotlin-lsp` on macOS ONLY; else bare binary from https://github.com/Kotlin/kotlin-lsp

    # =+= PyPi
    "poetry"  # TODO: debian can provide this, as can brew; fallback pip global

    # =+= npm
    "pnpm"  # TODO: do `npm i -g pnpm` on non-brew
    "bitwarden-cli"  # TODO: do `pnpm install -g @bitwarden/cli` on non-brew
    "pyright"  # TODO: brew provides; else `pnpm i -g pyright`
    "typescript"  # TODO: brew provides; else `pnpm i -g typescript`
    "typescript-language-server"  # TODO: brew provides; else `pnpm i -g typescript-language-server`
)

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
