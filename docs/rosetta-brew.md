# Rosetta brew

Some tooling only exists for x86_64. So every Apple Silicon Mac from Big Sur 11 through Tahoe 26 carries a second Homebrew: an x86_64 one in `/usr/local`, run under Rosetta 2, next to the native one in `/opt/homebrew`. It gets every formula the native brew gets (the `020-brew-packages` and `030-brew-extras` lists), but no casks, and no VM or container engine (see `nativeArch` below). `intel` and `arm` switch a terminal between the two worlds.

## Why it is pinned

Homebrew made every Intel macOS configuration Tier 3 in 7.0.0 and stopped building Intel bottles. Under Rosetta, brew *is* an Intel brew in every respect that matters: `RUBY_PLATFORM` is x86_64, it wants `/usr/local`, and it picks the unprefixed bottle tags (`sonoma`, `ventura`). The upstream installer has refused x86_64 outright since Homebrew/install e078684 (2026-09-04).

So the Rosetta brew is always era-pinned. It uses the `"<series>-amd64"` rows of `.chezmoidata/brew-tiers.toml` that already serve real Intel Macs (see [Homebrew on older macOS](homebrew-older-macos.md)): Big Sur through Ventura get their own eras, and Sonoma through Tahoe get the `current` era (brew 6.0.20, core at 2026-06-14), whose `sonoma` Intel bottles brew accepts on 14, 15 and 26 alike. A pinned brew never updates, so Homebrew's planned removal of x86_64 (in or after September 2027) does not reach it.

Homebrew never treated Intel Golden Gate 27 as supported: no x86_64 `golden_gate` bottles were ever built, and 27 is the last release with general-purpose Rosetta at all. So the Rosetta brew stops at 26.

## How it is installed

Three hookscripts, masked by `.chezmoiignore.tmpl` everywhere except Apple Silicon with `macos.major <= 26`, render the same shared templates as their native counterparts. They add the template key `brewArch = "amd64"` (and force `nativeArch` to false):

| Rosetta | Native | Shared template |
|---|---|---|
| `006-homebrew-x86` | `005-homebrew` | `homebrew-install.sh` |
| `021-brew-packages-x86` | `020-brew-packages` | `brew-packages-macos.sh` |
| `031-brew-extras-x86` | `030-brew-extras` | `brew-extras-macos.sh` |

`posix-preamble.sh` does the rest:

- **Tier lookup.** It looks the tier up with `brewArch` in place of `.chezmoi.arch`.
- **Prefix.** It sets `CHEZMOI_HOMEBREW_PREFIX=/usr/local` and `BREW_SECONDARY=1`.
- **Re-exec under Rosetta.** It re-executes the script with `arch -x86_64 /bin/bash -e`, so that `uname -m`, brew and every formula it runs are x86_64.
- **Clean environment.** It strips the native prefix from `PATH` and unsets the native `HOMEBREW_*` variables inherited from chezmoi.

`load_brew` loads only `/usr/local` in such a script. Native scripts on Apple Silicon, for their part, never fall back to `/usr/local`, so a missing `/opt/homebrew` can't quietly turn into installing into the x86_64 prefix. The installer skips the `launchctl` PATH for the Rosetta brew, so launchd keeps the native prefix first.

What stays with the native brew:

- casks
- the brew-gem gems
- `brew services` (languagetool)
- rustup and `~/.cargo` (shared by both arches)
- the `/Library/Java` openjdk link

## `intel` and `arm`

`.commonprofile` is Rosetta-aware on those hosts. A login shell that is translated (`sysctl.proc_translated` is 1) loads the `/usr/local` brew and its era environment instead of the native one. `intel` and `arm` replace the current shell with a fresh login shell under `arch -x86_64` or `arch -arm64`. The environment starts from `env -i` plus only what a real login carries: `HOME`, `USER`, `TERM`, `LANG`, `TMPDIR`, `SSH_AUTH_SOCK` and similar. So `path_helper` rebuilds `PATH` and the shell comes up as if you had logged in natively on that arch. Universal binaries started from an `intel` shell run as x86_64.

Native shells keep Apple's default `PATH`, so `/usr/local/bin` sits after `/opt/homebrew/bin`. A formula present only in the Rosetta brew is therefore still found from a native shell, and runs translated.

Neither function exists on Intel Macs, Golden Gate and later, Linux or Windows.

### chezmoi

chezmoi must run natively. An x86_64 chezmoi would render every template for Intel. `.chezmoiignore.tmpl` refuses to render at all when chezmoi is amd64 but the host's prefix is `/opt/homebrew`, and the preamble refuses translated native scripts as a backstop. Inside an `intel` shell, `chezmoi` is a function that runs the native binary under `arch -arm64`, without the Rosetta brew's environment. That binary is brew's, or the get.chezmoi.io one in `~/.local/bin`.

## `nativeArch`

`[data] nativeArch` in `.chezmoi.toml.tmpl` says whether the environment runs on the hardware's own instruction set.

- **True:** natively, or through a hypervisor (a VM or WSL2, whose guest is native code on the host CPU).
- **False:** the binaries are translated (Rosetta, Prism on Windows on ARM, qemu-user/FEX/box64 on Linux).

How it is detected:

| OS | Check |
|---|---|
| macOS | `sysctl.proc_translated` |
| Linux | `uname -m` against `.chezmoi.arch` |
| Windows | `Win32_Processor.Architecture` against `.chezmoi.arch` |

It gates the VM and container engines (apple/container and socktainer, colima, lima, lima-additional-guestagents) on every OS. A translated copy would duplicate the hypervisor stack.

On Linux this is on top of the existing `CONTAINERIZED` gate. The published Docker images are built on native runners for each arch, so `nativeArch` is true but `CONTAINERIZED` is 1, and they have no lima. The WSL tarballs, re-applied as WSL, do have it.

Like any new data key, it needs one `chezmoi init` after pulling.

## Leaving 26 behind

On a Mac upgraded to Golden Gate 27, the three scripts are masked and `intel`/`arm` stop being rendered. The `/usr/local` brew is left on disk, unmanaged. Remove it by hand, or keep using `/usr/local/bin/brew` under `arch -x86_64` for as long as Rosetta runs it.

The longer-term routes to an x86_64 userland are:

- **MacPorts:** `build_arch x86_64` or `+universal`. It publishes `+universal` archives for darwin 27; pure x86_64 builds from source.
- **x86_64 Linux** under Rosetta for Linux, in a Lima or UTM VM, which survives the end of general-purpose Rosetta.
