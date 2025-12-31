# My dotfiles

[![wakatime](https://wakatime.com/badge/github/regulad/dotfiles.svg)](https://wakatime.com/badge/github/regulad/dotfiles)

Supported environments:

- Termux
    - NOTE: `termux-exec` doesn't seem to hook the `execve()` syscall from the hookscript's shebang when chezmoi calls it, so the hookscript needs to be run manually after each apply.
- macOS
- Debian or Red Hat-based GNU/Linux
    - Including under WSL with Windows integration
- (Windows) NT `cmd` (via `autorun.cmd`)

Supported shells:

- `zsh`
- `bash` (fallback only)
- `cmd` (NT)

## Hookscripts

*nix-like platforms (termux, macOS, GNU/Linux) will automatically install required dependencies thanks to the `./run_sync.sh` hookscript.

TODO: NT hookscript

## *nix Install

```bash
# Preferred: install with native package manager
apt/pkg/dnf/brew install chezmoi
# Alternative: install to .local/bin
sh -c "$(curl -fsLS get.chezmoi.io/lb)"
export PATH="$PATH:$HOME/.local/bin"

# Initalize & run first-time dependency install
chezmoi init regulad
~/.local/share/chezmoi/run_sync.sh
source ~/.local/share/chezmoi/dot_commonrc

# Configure bw for templating
bw config server https://vw.regulad.xyz  # this is my server, obviously. replace w/ yours
bw login --apikey  # stdio needed

# Final apply
chezmoi apply
```

## TODOs

- [ ] Addl. language server configurations in nvim
- [ ] Emit warnings in vim and bash
- [ ] Brew on permissionless systems w/ gentoo-style custom prefixes
- [ ] Annotate `rc`s with philosophy (no network requests, fast boot, etc.
- [ ] Adopt `corepack` for installing `pnpm`
- [ ] Finalize & memorize nvim keybinds (lock it in, dude!)

