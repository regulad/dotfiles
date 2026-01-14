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
- Windows 10 ESU/11 `cmd` (via `autorun.cmd`)
    - Installs scoop

Supported shells:

- `zsh`
- `bash` (fallback only)
- `cmd` (NT)

## Hookscripts

*nix-like platforms (Termux, macOS, GNU/Linux) will automatically install required dependencies thanks to the `./run_posix-sync.sh` hookscript.

Similarly NT platforms use `run_nt-sync.cmd` for dependency installation.

## *nix Install

```bash
# Preferred: install with native package manager
apt/pkg/dnf/brew install chezmoi
# Alternative: install to .local/bin
sh -c "$(curl -fsLS get.chezmoi.io/lb)"
export PATH="$PATH:$HOME/.local/bin"

# Initalize & run first-time dependency install
chezmoi init regulad
~/.local/share/chezmoi/run_posix-sync.sh
source ~/.local/share/chezmoi/dot_commonrc

# Configure bw for templating
bw config server https://vw.regulad.xyz  # this is my server, obviously. replace w/ yours
bw login --apikey  # stdio needed

# Final apply
chezmoi apply
```

## NT Install

```cmd
# Install dependencies via scoop
scoop install chezmoi bitwarden-cli git

# Initialize chezmoi
chezmoi init regulad

# Configure bw for templating
bw config server https://vw.regulad.xyz  # replace with your server
bw login --apikey

# Apply dotfiles
chezmoi apply
```

The `autorun.cmd` will automatically set up Clink and doskey macros (`pipx`, `vi`, `chezmoi-cd`, `ssh-privpub`) on each shell startup.

## Notes

### VSCode

Make sure you add any extensions you'd like to download to `vscode-extensions.txt`. The newest version of every extension listed in the file is installed on each apply.

### Packages: winget/scoop/apt/pkg/brew/pnpm/uv/whatever

Remember to define the package in the correct hookscript (i.e. `run_posix-sync.sh` or `run_nt-sync.sh`)

## TODOs

- [ ] Zsh: Finalize & memorize zsh backsearch keybinds
- [ ] Nt: Write NT self-bootstrapping script
- [x] Doc: Emit warnings in vim and bash
- [ ] Doc: Annotate `rc`s with philosophy (no network requests, fast boot, etc.
- [ ] Brew: Brew on permissionless systems w/ gentoo-style custom prefixes
- [ ] Nvim: Finalize & memorize nvim keybinds (lock it in, dude!)
- [x] Nvim: Fix nvim newline behaviour
- [x] Nvim: Relative + absolute line numbers in nvim
- [x] Nvim: Addl. language server configurations in nvim
- [ ] Nvim: ensure that treesitter and vim-polyglot aren't clobbering each other
