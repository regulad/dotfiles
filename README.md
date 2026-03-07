# Parker Edward "regulad" Wahle's Configuromicon

[![wakatime](https://wakatime.com/badge/github/regulad/dotfiles.svg)](https://wakatime.com/badge/github/regulad/dotfiles)

Welcome to my configuromicon. This monolithic repository contains the configurations for most of the tools that I use on an everyday basis. 

It's currently backed by `chezmoi`. 
Running `chezmoi apply` after a proper setup will enable deterministic restoration of my environment.
After running `chezmoi apply` and restarting your shell, you can also use `quarantine` to launch an ephemeral environment with the same configuration. Useful for testing harmful software or for vibe-coding. `~/repositories` is mapped through to the VM.

Additionally, it includes a couple custom tools that I use; for example, a `pycalc3` command is provided that brings up an ephemeral IPython environment for quick CPE & physics calculations.

The default keyboard layout is of my [Keychron Q6 Max](https://www.keychron.com/products/keychron-q6-max-qmk-via-wireless-custom-mechanical-keyboard?variant=40799762972761). You should be able to replace the `base.json` with your keyboard's layout, but no guarantees are made. 

*This project is AGPL-3.0 licensed. Small request: if you choose to contribute, please do so on the GitHub fork network. This is only a request, AGPL-3.0 does not obligate you to share private modifications unless they are used through a network (i.e. shell account).*

***PLEASE NOTE**: While all files provided in this repository are AGPL-3.0 licensed, the final compiled docker image and workspace contain non-libre assets like the Android SDK.*

## Shell configurations

Supported environments:

- macOS latest (w/ `brew`)
- Debian GNU/Linux >= 13
- Ubuntu GNU/Linux >= 25.10
- Fedora GNU/Linux >= 42
- Windows 10 ESU/11 `cmd` (via `autorun.cmd`)

Brew will be installed on Darwin and Linux if it is not already installed. Rootless installs are supported but a warning will be emitted since I can't test every edge case.

Linux environments are preferred in the following order:

1. Fedora
    - Why? DNF5 is fast, deterministic, and RHEL is the industry standard.
    - I trust Red Hat more to ship reliable and efficient software more than I trust Canonical.
2. Ubuntu
    - Why? Homebrew builds against Ubuntu, and not base Debian.
    - Don't get it twisted, I don't agree with Canonical's decision to replace the coreutils with rust rewrites.
3. Debian
    - I like Debian, I would place it above Ubuntu if Homebrew didn't delegate Debian to "Tier 2" support.

All of the above environments are available in Docker pours (see the packages menu on the right).

> *NOTE:* Termux is no longer supported in a first-class fashion. I don't have an Android phone.
> Simialrly, RHEL is no longer supported in a first-class fashion. This setup is for desktop use.

Supported shells:

- `zsh` (Preferred)
- `bash`
- `cmd` (NT-only)

I have no intent to support PowerShell: I don't want to spend half of the time in my shell wrestling with different eras of features and aliases that do not have the same signature as the builtins they shadow.

### Hookscripts

POSIX-like platforms will automatically install required dependencies thanks to the `./run_posix-sync.sh` hookscript.

Similarly NT platforms use `run_nt-sync.cmd` for dependency installation.

### *nix Install

```bash
# Preferred: install with native package manager
apt/pkg/dnf/brew install chezmoi
# Alternative: install to .local/bin
sh -c "$(curl -fsLS get.chezmoi.io/lb)"
export PATH="$PATH:$HOME/.local/bin"

# Initalize & run first-time dependency install
CHEZMOI_USE_DUMMY=1 chezmoi init regulad
# CHEZMOI_USE_DUMMY instructs chezmoi to not attempt to apply any secrets.
chezmoi apply --exclude encrypted

# Configure bw for templating
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

Make sure you add any extensions you'd like to download to `vscode-extensions.txt`. The newest version of every extension listed in the file is installed on each apply.

### Packages: winget/scoop/apt/pkg/brew/pnpm/uv/whatever

Remember to define the package in the correct hookscript (i.e. `run_posix-sync.sh` or `run_nt-sync.sh`)

## TODOs

- [x] Cattle: Add userspace tailscale in vagrant for opencode/sus software
- [x] Nt: Write NT self-bootstrapping script
- [x] Doc: Emit warnings in vim and bash
- [ ] Doc: Annotate `rc`s with philosophy (no network requests, fast boot, etc.
- [x] Brew: Brew on permissionless systems w/ gentoo-style custom prefixes
- [ ] Brew: Use zerobrew if available on macOS (way fuckin faster)
- [x] Nvim: Fix nvim newline behaviour
- [x] Nvim: Relative + absolute line numbers in nvim
- [x] Nvim: Addl. language server configurations in nvim
- [ ] Nvim: ensure that treesitter and vim-polyglot aren't clobbering each other
- [x] Hook: Break java LTS and minimum fedora version into separate vars

## LLM Usage

Some trivial chunks of code in this project have been generated by LLMs. All subroutines that have been generated have been explicitly marked as such.

Example:

```bash
# Generated by an AI assistant developed by Perplexity AI (model: GPT-5.2).
# Purpose: Updates a file line matching "^# DEP_HASH:" to "# DEP_HASH:<new_hash>" using awk.
```

I have quite the love-hate relationship with LLMs. Under no cirmcumstances will I knowingly use an LLM to generate any user-facing documentation. Every time you choose to use an LLM to generate documentation for your code, a young programmer-ling is turned away from trying to contribute to your project.
