# Hookscripts

POSIX-like platforms will automatically install required dependencies thanks to the hookscripts in `.chezmoiscripts/00-macos/` and `.chezmoiscripts/00-linux/` (plus `01-fedora/` and `02-bluefin/` layers on Linux).

Similarly NT platforms use the hookscripts in `.chezmoiscripts/00-nt/` for dependency installation.

Every POSIX hookscript opens with one of two shared preambles from `.chezmoitemplates/`:

- `posix-preamble.sh` -- platform guards, lazy `can_sudo`/`require_sudo`, `load_brew` (loads brew if present, sets `HAS_BREW`), and `MANAGER`. For scripts that merely prefer brew and have a fallback.
- `posix-preamble-brew.sh` -- the above plus `require_brew`, the brew counterpart of `require_sudo`: fails fast if brew is missing and guarantees `$HOMEBREW_PREFIX` is set. For scripts whose whole job is brew work (package lists, casks, taps, anything that reads `$HOMEBREW_PREFIX`).

On macOS, `003-macos-prereqs` runs first and installs the Apple-shipped prerequisites on every Mac: the Xcode Command Line Tools through `softwareupdate`, non-interactively, at no older a version than brew accepts on that macOS (so a macOS upgrade gets the matching CLT on the next apply, Xcode.app or not); the license of an installed Xcode.app; and Rosetta 2 on Apple Silicon. So all of it is in place before brew, MacPorts or any source build, and when it can't be (softwareupdate offers no CLT, say) the apply stops there rather than failing later in brew. `015-brew-taps` then adds the third-party brew taps; everything installed from them is written as `user/repo/name`. Brew itself is installed by `005-homebrew` on both platforms, from `.chezmoitemplates/homebrew-install.sh`, before anything that needs it. It is a `run_after_`, so a host whose brew was removed gets it back on the next apply. On Apple Silicon up to Tahoe 26, `006-homebrew-x86`, `021-brew-packages-x86` and `031-brew-extras-x86` do the same for a second, x86_64 brew in `/usr/local` under Rosetta, from the same templates; see [Rosetta brew](rosetta-brew.md).

The brew prefix is decided once, at `chezmoi init`, as `.homebrewPrefix` (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel, `/home/linuxbrew/.linuxbrew` on Linux) and rendered into every static file that has to name a brew binary: tmux, gpg-agent, the Touch ID PAM lines, the Chrome gpgme manifest, `.bootstrap.sh`. Hookscripts get the same answer at runtime from `brew shellenv`. **After pulling a version of this repo that introduced `.homebrewPrefix`, `.macos.series`, `.nativeArch` or `.machine`, run `chezmoi init` once** -- `.chezmoi.toml.tmpl` is only re-rendered by init, and templates reference these keys (`.machine` in `.chezmoiignore.tmpl`, so every chezmoi command fails until then).

### Applying a Mac over SSH

Some macOS changes are only granted through a prompt on the Mac's own screen, which an SSH session cannot show. The scripts that run into one print a `warning:` instead of stopping the apply, and they are `run_after_` so the next apply from the Mac's own session (in person or over Screen Sharing) finishes the job:

- `140-ca-certs`: certificate trust settings ("no user interaction was possible"). Apple supports no non-interactive way short of MDM.
- `141-client-cert`: an SSH session sees the login keychain locked, even while you are logged in at the Mac. `security unlock-keychain` in that session unlocks it.
- `170-firefox-policies`: writing into `Firefox.app` takes App Management. Allowing full disk access for remote users (System Settings → General → Sharing → Remote Login) grants it over SSH too.

## Per-model hookscripts

`.chezmoiscripts/99-<os>-<make>-<model>/` holds hookscripts for one computer model only, usually a workaround for its firmware or hardware. For example, `99-nt-ASUSTeK+COMPUTER+INC.-ROG+Flow+Z13+GZ302EA_GZ302EA/` replaces the ROG Flow Z13's broken S0ix sleep with hibernation. `<os>` is the tier name (`nt`, `macos`, `linux`). `<make>` and `<model>` are exactly what the firmware reports in its SMBIOS System Information (`hw.model` on a Mac), put through `urlquery`, so the name is valid on NT and Unix alike. `chezmoi data` shows the raw strings as `.machine.make` and `.machine.model`, and `.chezmoiignore.tmpl` masks every such directory except the host's own. Containers and WSL report no model, so they never get one. Being `99`, these scripts run after everything in `00-*`, the sign-in reminders included. To get the directory name for a new machine:

```bash
chezmoi execute-template '99-nt-{{ urlquery .machine.make }}-{{ urlquery .machine.model }}'
```

(A model ending in `.` also has that dot escaped as `%2E`, since Win32 strips trailing dots.)

Windows updates tend to put such workarounds back. A Windows one can be a `run_onchange_` `.tmpl` that renders `{{ output "cmd.exe" "/d" "/c" "ver" | trim }}` into a comment, as `010-hibernate-not-s0ix` does, so that every build, monthly update revision included, re-runs it. That only works if the script is idempotent and checks before it elevates, so that a re-run with nothing to fix raises no UAC prompt.

## Packages: winget/scoop/apt/pkg/brew/pnpm/uv/whatever

Remember to define the package in the correct hookscript under `.chezmoiscripts/00-macos/`, `.chezmoiscripts/00-linux/` or `.chezmoiscripts/00-nt/`.

## Running one script

Scripts can be applied individually, addressed by their stripped target name, which is useful when bringing up a new host in stages:

```bash
chezmoi apply ~/.chezmoiscripts/00-macos/005-homebrew.sh
```

## C/C++ language support

Vim installs `coc-clangd` from `dot_coc-extensions.txt` through the plugin
bootstrap. Neovim enables `clangd` through its native LSP client and
`nvim-lspconfig`. Both use the `clangd` executable on `PATH`.

| Host | Provisioned package |
| --- | --- |
| Windows | Scoop `clangd` |
| Ubuntu/Debian | apt `clangd` |
| Fedora | dnf `clang-tools-extra` |
| Bluefin | Homebrew `llvm` |
| macOS | Homebrew `llvm`; `.commonprofile` appends its keg-only `bin` directory to `PATH` |

CoC also needs Node.js, which is already provisioned on every supported host.
clangd provides completion, diagnostics, navigation, and formatting; a separate
`clang-format` executable is not required for LSP formatting. Building code still
requires the project's compiler and SDK/headers. For project-aware analysis,
generate `compile_commands.json` (for example, configure CMake with
`-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` using Ninja or Makefiles). For a small project,
`compile_flags.txt` can supply include paths and compiler flags instead.
