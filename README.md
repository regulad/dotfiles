# My dotfiles

[![wakatime](https://wakatime.com/badge/github/regulad/dotfiles.svg)](https://wakatime.com/badge/github/regulad/dotfiles)

Supported environments:

- Termux
- macOS
- Debian or Red Hat-based GNU/Linux
    - Including under WSL with Windows integration
- (Windows) NT `cmd` (via `autorun.cmd`)

## Hookscripts

*nix-like platforms (termux, macOS, GNU/Linux) will automatically install required dependencies thanks to the `./run_sync.sh` hookscript.

TODO: NT hookscript

## Install

```bash
# Preferred: install with native package manager
apt/pkg/dnf/brew install chezmoi
# Alternative: install to .local/bin
sh -c "$(curl -fsLS get.chezmoi.io/lb)"
export PATH="$PATH:$HOME/.local/bin"

# Initalize & run first-time dependency install
chezmoi init regulad
~/.local/share/chezmoi/run_sync.sh

# Configure bw for templating
bw config <...>
bw login <...>

# Final apply
chezmoi apply
# Profit!
```
