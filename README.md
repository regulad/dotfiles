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

- macOS latest (w/ `brew`)
- Bluefin (Universal Blue's atomic Fedora desktop)
- Ubuntu GNU/Linux >= 25.10
- Fedora GNU/Linux >= 44
- Windows 11 `cmd`

Brew will be installed on macOS and Linux if it is not already installed. Rootless installs are supported but a warning will be emitted since I can't test every edge case.

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

### Hookscripts

POSIX-like platforms will automatically install required dependencies thanks to the hookscripts in `.chezmoiscripts/00-posix/`.

Similarly NT platforms use the hookscripts in `.chezmoiscripts/00-nt/` for dependency installation.

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

Make sure you add any extensions you'd like to download to `vscode-extensions.txt`. The newest version of every extension listed in the file is installed on each apply, and any installed extension not listed in the file is uninstalled.

### Theos

`.chezmoiscripts/00-{linux,macos}/125-theos.sh` install [Theos](https://theos.dev) into `~/theos`, from the [roothide](https://github.com/roothide/theos) fork rather than base Theos. Each is a stub around that fork's `bin/install-theos`, which is the entire install story and the only supported entry point — it owns the dependency lists, the fakeroot alternative, the toolchain tarball URLs and the SDK fetch, all of which move independently of the docs. `.commonprofile` exports `$THEOS` and puts `$THEOS/bin` on `PATH`.

Three things worth knowing:

- **Atomic hosts don't get it.** `install-theos` opens with a privileged system-package transaction, chosen by what's on `PATH` rather than by distro ID — and since Universal Blue images ship `dnf`, it takes the redhat branch and tries to install a dozen build dependencies into a read-only `/usr`. That exits 3 and fails the apply, so `.chezmoiignore` masks the Linux hook whenever `/run/ostree-booted` exists. There's no brew stand-in the way `022-brew-packages.sh` stands in for `020-dnf-packages.sh`; the installer has no notion of a prefix other than the system one. `~/theos` is still writable, so a host that wants the toolchain can layer the dependencies with `rpm-ostree` and run the hook by hand, or install into a toolbox/distrobox — `.commonprofile` only adds `$THEOS/bin` to `PATH` when the directory exists, so either works with no further changes. The published container images are built `FROM` ordinary fedora/ubuntu and are not ostree-booted, so they keep Theos.
- **macOS needs the full Xcode**, not the Command Line Tools — Theos builds against the iOS/tvOS platform toolchains that only Xcode.app ships, and `install-theos` exits 3 without it. Nothing here can install it: there is no cask, and `mas` cannot drive it.
- **The Linux toolchain is the Swift one.** The installer asks interactively; the hook can't answer, because an unattended apply has no terminal and the `read` would kill the install, so it sets `$CI` to skip the prompt and `sed`s the hardcoded default from no to yes. That gets the larger kabiroberai `swift-toolchain-linux` build rather than the smaller L1ghtmann `iOSToolchain`. For the non-Swift one, remove `$THEOS/toolchain/linux/iphone` and re-run the hook without that `sed`.

### Packages: winget/scoop/apt/pkg/brew/pnpm/uv/whatever

Remember to define the package in the correct hookscript under `.chezmoiscripts/00-posix/` or `.chezmoiscripts/00-nt/`

### WSL: `wsl-deploy` and `wsl-enter`

Two Windows-side helpers in `~/.local/bin`, exposed to `cmd` by doskey macros in `.doskey.mac`. They invoke by full path on purpose: `~/.local/bin` is only put on `PATH` by `.commonprofile`, which is POSIX shells only.

`wsl-deploy [fedora|ubuntu]` installs the newest built image as `regulad-<flavor>`:

```console
wsl-deploy                    # newest ubuntu image for this architecture
wsl-deploy fedora
wsl-deploy.ps1 -SetDefault    # and make it what a bare `wsl` starts
```

It finds the newest unexpired `wsl-<flavor>-<arch>` artifact, downloads it with a progress readout, and imports it to `%LOCALAPPDATA%\wsl\regulad-<flavor>`. Notable behaviour:

- **It is destructive.** If `regulad-<flavor>` already exists, continuing *unregisters* it — the VHD and everything in it is gone, with no undo. It prompts first; `-Force` skips the prompt.
- Each import records its provenance in `deployed-from.json` next to the VHD, so later runs can tell you whether the installed instance is already the newest build or is behind one. Nothing in WSL tracks this on its own. The file lives in the install directory precisely so `wsl --unregister` takes it with the instance rather than leaving a stale claim behind.
- Afterwards it offers, y/N, to make the instance the default distribution — worth taking, since the default is otherwise whatever was installed first, frequently `docker-desktop`.
- Images are published as Actions artifacts rather than release assets because they are ~5 GB against a 2 GB release-asset cap. Artifacts expire after 14 days, so if none is found, push to `master` or re-run the Docker workflow.
- Unless `-NoLaunch` is passed, the import opens a shell, which is what triggers `/etc/oobe.sh`. That reads the Bitwarden API credentials from the Windows host's own `%USERPROFILE%\.secrets\.bwrc` over DrvFs and runs the privileged apply; it will ask for the vault master password. To re-run it later: `wsl -d regulad-<flavor> -u root -- /etc/oobe.sh`.

`wsl-enter [fedora|ubuntu]` opens a shell in an already-deployed instance, in the directory you called it from:

```console
D:\repositories\foo> wsl-enter        # lands in /mnt/d/repositories/foo
```

It installs nothing and destroys nothing. Where the current directory is something WSL cannot see — a UNC path, a mapped network drive, or a non-filesystem PowerShell provider like `HKLM:` — it starts at `$HOME` and says so, rather than failing the launch and leaving you with no shell. `-NoCd` always starts at `$HOME`.

## TODOs

- [x] Nt: Write NT self-bootstrapping script
- [x] Doc: Emit warnings in vim and bash
- [x] Brew: Brew on permissionless systems w/ gentoo-style custom prefixes
- [x] Nvim: Fix nvim newline behaviour
- [x] Nvim: Relative + absolute line numbers in nvim
- [x] Nvim: Addl. language server configurations in nvim
- [ ] Nvim: ensure that treesitter and vim-polyglot aren't clobbering each other
- [x] Hook: Break java LTS and minimum fedora version into separate vars
- [ ] Shell: direnv-style watcher script executor with script verification
- [ ] WSL: IPv6 default route via a localhost-bound WireGuard server on the Windows side, with a host-deterministic ULA and NAT66. Mirrored networking was the only mode that gave WSL IPv6, and `.wslconfig` moved to NAT; NAT provides no routable IPv6 and there is no setting that adds it.
