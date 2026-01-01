# My dotfiles

[![wakatime](https://wakatime.com/badge/github/regulad/dotfiles.svg)](https://wakatime.com/badge/github/regulad/dotfiles)

Supported environments:

- Termux latest
    - NOTE: `termux-exec` doesn't seem to hook the `execve()` syscall from the hookscript's shebang when chezmoi calls it, so the hookscript needs to be run manually after each apply.
- macOS latest (w/ `brew`)
- Debian GNU/Linux (tested against Ubuntu 24.04)
    - Including under WSL with Windows integration
    - Installs brew
- Red Hat-based GNU/Linux (tested against Fedora >= 42 and RHEL >= 10)
    - Including under WSL with Windows integration
    - Installs brew
- (Windows 11) NT >= 19045 `cmd` (via `autorun.cmd`)
    - Installs choco

Supported shells:

- `zsh`
- `bash` (fallback only)
- `cmd` (NT)

## Hookscripts

*nix-like platforms (Termux, macOS, GNU/Linux) will automatically install required dependencies thanks to the `./run_sync.sh` hookscript.

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

## NT Install

TODO

In summary: install chezmoi, bw, and git through scoop, init w/ chezmoi, login to bw, chezmoi apply and pray

## TODOs

- [ ] Addl. language server configurations in nvim
- [ ] Emit warnings in vim and bash
- [ ] Brew on permissionless systems w/ gentoo-style custom prefixes
- [ ] Brew casks on macOS only (stuff like Bitwarden depends on state)
- [ ] Annotate `rc`s with philosophy (no network requests, fast boot, etc.
- [ ] Adopt `corepack` for installing `pnpm`
- [ ] Finalize & memorize nvim keybinds (lock it in, dude!)
- [ ] Fix nvim newline behaviour
- [ ] Get `uv` building on termux
- [ ] Bitwarden cask/appstore install on macOS for the BW ssh keychain manager
- [ ] Global crates like https://github.com/ExPixel/cargo-disasm
