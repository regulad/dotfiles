# Parker Edward "regulad" Wahle's Configuromicon

[![wakatime](https://wakatime.com/badge/github/regulad/dotfiles.svg)](https://wakatime.com/badge/github/regulad/dotfiles)

Welcome to my configuromicon. This monolithic repository contains the configurations for most of the tools that I use on an everyday basis. 

It's currently backed by `chezmoi`. 
Running `chezmoi apply` after a proper setup will enable deterministic restoration of my environment.

Additionally, it includes a couple custom tools that I use; for example, a `pycalc3` command is provided that brings up an ephemeral IPython environment for quick CPE & physics calculations.

The default keyboard layout is of my [Keychron Q6 Max](https://www.keychron.com/products/keychron-q6-max-qmk-via-wireless-custom-mechanical-keyboard?variant=40799762972761). You should be able to replace the `base.json` with your keyboard's layout, but no guarantees are made. 

*This project is AGPL-3.0 licensed. Small request: if you choose to contribute, please do so on the GitHub fork network. This is only a request, AGPL-3.0 does not obligate you to share private modifications unless they are used through a network (i.e. shell account).*

***PLEASE NOTE**: While all files provided in this repository are AGPL-3.0 licensed, the final compiled docker image and workspace contain non-libre assets like the Android SDK.*

## Shell configurations

Supported environments:

- macOS 10.15 (Catalina) and newer, Apple Silicon and Intel (w/ `brew`; releases Homebrew no longer bottles for get an era-pinned brew that still installs bottles, see [docs/homebrew-older-macos.md](docs/homebrew-older-macos.md))
- Bluefin (Universal Blue's atomic Fedora desktop)
- Ubuntu GNU/Linux >= 25.10
- Fedora GNU/Linux >= 44
- Windows 11 `cmd`

Brew will be installed on macOS and Linux if it is not already installed. This needs sudo: brew goes to its standard prefix, and the rootless install mode Homebrew itself does not support is not offered here.

Linux environments are preferred in the following order:

1. Fedora
    - Why? DNF5 is fast, deterministic, and RHEL is the industry standard.
    - I trust Red Hat more to ship reliable and efficient software more than I trust Canonical.
    - Bluefin counts here: it is atomic Fedora. `/usr` belongs to the bootc image and is read-only, and rpm-ostree layering is an explicit anti-pattern on those images, so CLI tooling comes from `brew` rather than `dnf`. That split is what `.chezmoiscripts/00-linux/run_after_022-brew-packages.sh.tmpl` exists for, and it tracks which packages the image already provides so they aren't shadowed by a second copy earlier on `PATH`.
2. Ubuntu
    - Why? Homebrew builds against Ubuntu, and not base Debian.

The Ubuntu and Fedora environments are available in Docker pours (see the packages menu on the right). Using `latest` will get you the newest Ubuntu image since fedora-based Docker images are pretty rare. Bluefin is not built here — it is a host you apply onto, not an image this repo produces.

> The Debian setup has been migrated to Ubuntu to follow software that tests against Ubuntu.

> Simialrly, RHEL is no longer supported in a first-class fashion. This setup is for desktop use.

Supported shells:

- `zsh` (Preferred)
- `bash`
- `cmd` (NT-only)

I have no intent to support PowerShell: I don't want to spend half of the time in my shell wrestling with different eras of features and aliases that do not have the same signature as the builtins they shadow.

### *nix Install

```bash
# Preferred: install with native package manager
apt/pkg/dnf/brew install chezmoi
# Alternative: install to .local/bin
sh -c "$(curl -fsLS get.chezmoi.io/lb)"
export PATH="$PATH:$HOME/.local/bin"
# run this instead on a macOS release older than 13 Ventura: chezmoi is a Go
# program, and each Go release drops old macOS (the symptom is dyld dying on a
# missing Security.framework symbol). Last chezmoi built before each cutoff:
# sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- -t v2.72.0   # macOS 12 Monterey
# sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- -t v2.64.0   # macOS 11 Big Sur
# sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- -t v2.52.0   # macOS 10.15 Catalina

# Initalize & run first-time dependency install
CHEZMOI_USE_DUMMY=1 chezmoi init regulad
# CHEZMOI_USE_DUMMY instructs chezmoi to not attempt to apply any secrets.
chezmoi apply --exclude encrypted

# Configure bw for templating (bw is brew's bitwarden-cli, installed by the apply above;
# on an era-pinned macOS it is that era's version)
bw config server https://vw.regulad.xyz  # this is my server, obviously. replace w/ yours
bw login --apikey  # stdio needed

# Final apply with real secrets
chezmoi init
chezmoi apply ~/key.txt  # bootstraps age
chezmoi apply
```

### NT Install

```cmd
# Install dependencies via scoop
scoop install chezmoi git

# Initalize & run first-time dependency install
CHEZMOI_USE_DUMMY=1 chezmoi init regulad
# CHEZMOI_USE_DUMMY instructs chezmoi to not attempt to apply any secrets.
chezmoi apply --exclude encrypted

# Configure bw for templating
bw config server https://vw.regulad.xyz  # this is my server, obviously. replace w/ yours
bw login --apikey  # stdio needed

# Final apply with real secrets
chezmoi init
chezmoi apply %USERPROFILE%\key.txt  # bootstraps age
chezmoi apply
```

The `autorun.cmd` will automatically set up Clink and doskey macros (`pipx`, `vi`, `chezmoi-cd`, `ssh-privpub`) on each shell startup.

## Notes

### VSCode

Make sure you add any extensions you'd like to download to `.chezmoidata/vscode.toml`. The newest version of every extension listed there is installed whenever the list changes, and any installed extension not listed is uninstalled. The extensions a listed one brings in (extension pack members and `extensionDependencies`) are kept, and an install or uninstall that still fails after its retries fails the apply. Copilot needs no entry: VS Code ships GitHub Copilot Chat built in.

### Packages

Remember to define the package in the correct hookscript under `.chezmoiscripts/00-macos/`, `.chezmoiscripts/00-linux/` or `.chezmoiscripts/00-nt/`. How the hookscripts fit together is in [docs/hookscripts.md](docs/hookscripts.md).

## Docs

Longer write-ups live in `docs/` (not deployed to `$HOME`):

- [Hookscripts](docs/hookscripts.md) -- the preambles, script order, the brew prefix, C/C++ language support.
- [Homebrew on older macOS](docs/homebrew-older-macos.md) -- era-pinned brew for releases Homebrew no longer bottles for, the Catalina floor, `brew update`, MacPorts, bootstrapping 10.x.
- [Rosetta brew](docs/rosetta-brew.md) -- the x86_64 brew in `/usr/local` on Apple Silicon up to Tahoe 26, `intel`/`arm`, and `nativeArch`.
- [Bottle mirror](docs/brew-mirror.md) -- every brew fetches bottles through a Nexus proxy of ghcr.io, except on GitHub-hosted runners.
- [Theos](docs/theos.md)
- [SSH server on Windows](docs/windows-sshd.md) -- the user-session `sshd`.
- [WSL](docs/wsl.md) -- `wsl-deploy` and `wsl-enter`.
- [Containers](docs/containers.md) -- which engine each host runs (wslc, apple/container, colima, podman) and the Docker Desktop and macOS podman removal.

## TODOs

- [x] Nt: Write NT self-bootstrapping script
- [x] Doc: Emit warnings in vim and bash
- [x] ~~Brew: Brew on permissionless systems w/ gentoo-style custom prefixes~~ (removed 2026-09: the rootless path was only ever quasi-supported; brew now requires sudo and its standard prefix)
- [x] Nvim: Fix nvim newline behaviour
- [x] Nvim: Relative + absolute line numbers in nvim
- [x] Nvim: Addl. language server configurations in nvim
- [x] Hook: Break java LTS and minimum fedora version into separate vars
- [ ] Shell: direnv-style watcher script executor with script verification
- [ ] Containers: no Docker Engine API socket shim exists for Windows yet. wslc keeps its dockerd inside its VM and exposes no socket or pipe to Windows (microsoft/WSL#40976), and has no compose (microsoft/WSL#40948), so `act`, testcontainers, `docker compose` and compose-based devcontainers have nothing to target on Windows. Revisit when wslc or a third-party shim serves one.
- [ ] WSL: IPv6 default route via a localhost-bound WireGuard server on the Windows side, with a host-deterministic ULA and NAT66. Mirrored networking was the only mode that gave WSL IPv6, and `.wslconfig` moved to NAT; NAT provides no routable IPv6 and there is no setting that adds it.
- [ ] CI: Windows test apply
