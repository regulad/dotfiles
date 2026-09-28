# Homebrew on older macOS

Mainline Homebrew only ships bottles (prebuilt binaries) for the macOS releases it calls Tier 1 -- as of September 2026 that is Sequoia 15, Tahoe 26 and Golden Gate 27, on Apple Silicon only. Everything older, and every Intel Mac, is Tier 3: brew still runs, but each `brew install` is a from-source build with no guarantee it succeeds. Intel is scheduled to stop running brew at all in or after September 2027. The bottles built while a release *was* Tier 1 are still on ghcr.io, though, so an old Mac -- the kind kept around for work newer macOS can't do, like USB sniffing -- is served by brew from that era instead:

- `.chezmoidata/brew-tiers.toml` maps each `(macOS series, arch)` tuple that is no longer Tier 1 (the series is the release as Homebrew names it: `11` and up, or `10.14`/`10.15`) to the last `Homebrew/brew` release tag whose docs still listed it as fully supported, and an era. Each era names one commit per tap, `core_commit` and `cask_commit`: the newest commit at which every formula in the lists still has that host's bottle, which can be weeks or months before the docs demotion, because bottles stop being built for an OS formula by formula. Each entry cites the upstream commit it came from. A tuple absent from the table is Tier 1 and gets mainline brew.
- `005-homebrew` does not use the upstream installer on such a host: no version of it pins a ref, every version ends with `brew update`, current ones refuse Intel and old releases, and older ones clone homebrew-core from a branch that no longer exists. Instead it reproduces the small, stable part of what the installer does -- the prefix directories with their `user:admin` ownership, a git checkout of Homebrew/brew at the era tag, the Intel `bin/brew` symlink -- then taps `homebrew/core` and `homebrew/cask` in full through that brew (the JSON API only describes current bottles, so the taps have to be real git checkouts) and checks each out at its era commit. Every apply re-verifies the pin, repo first with git alone, then the taps.
- `posix-preamble.sh` and `.commonprofile` export `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_INSTALL_FROM_API=1` on such a host, so neither a hookscript nor an interactive shell can move brew off the pin or make it read the API.
- `brew_trust` in the preamble wraps `brew trust`, which a 2023-era brew doesn't have; the tap and formula lists work unchanged on both.

## Package lists

The package lists are written against current homebrew-core and homebrew-cask, and adapt themselves to the era inline: each list resolves the era name at the top, and an entry that had a different name at that checkout (`ruby@4` was `ruby`, `handbrake-app` was `handbrake`) or that did not exist there yet (retry and sshpass before 2024, fernflower and git-xet before 2026, a dozen casks such as claude and codex) or whose cask declares a floor or arch the host fails (chatgpt and forklift on Ventura, kde-connect anywhere but Apple Silicon Sonoma) is a template conditional next to the current entry, so the list still reads as one list and nothing is fetched from anywhere but the pinned taps. Everything left is installed from the era's tap commits with bottles. The evidence behind each conditional is the per-era tap audit of 2026-09-28, summarised in the data file's comments. (The deleted homebrew-cask-versions tap was audited through its surviving fork network; GitHub keeps a deleted repository's forks, and a commit SHA identifies the content regardless of which fork serves it.)

## The floor

The floor is Mojave (10.14), and it is set by bottle hosting, not by brew. Homebrew moved bottles from Bintray to ghcr.io in April 2021 and copied only the bottle live in each formula at that moment; Mojave and Catalina were demoted after that, so every formula in these lists at their era commits still has a bottle on ghcr.io today (checked blob by blob). High Sierra and older were demoted before it: their era brews only know the dead Bintray URL scheme, and of 30 sampled formulae at their era commits, 6, 1 and 1 still have a bottle on ghcr.io. A newer brew that still runs there has nothing left to fetch. Mojave in particular loses more of the lists than the later eras, since much of what is in them did not exist in 2021, and it has no `mas` bottle at all, so the App Store script skips itself there. The same era conditionals reach the tooling scripts: `uv` comes from MacPorts before 2024, `hatch` and two language servers are absent on Mojave (the language servers go through pnpm instead), and `typescript-language-server` likewise on Catalina. Expect `uv`'s managed Python downloads to be the weakest link on Mojave; python-build-standalone's macOS floor is not verified here.

## `brew update`

`brew update` is the one command that undoes all of this: it moves brew and both taps to upstream HEAD, and on 10.x leaves a brew that will not start. So on an era-pinned host it never runs. The env above stops the implicit one, nothing in this repo runs the explicit one (the upstream installer, which does, is not used on such a host), and `.commonprofile` wraps `brew` so that `brew update` prints a warning and does nothing; `brew! update` is the real binary for when you mean it. If it does get run, the next `chezmoi apply` re-pins: `005-homebrew` resets the brew repo with git alone, by path, before the first `brew` invocation, then the taps.

## Other caveats

Pre-Sonoma hosts have no `/etc/pam.d/sudo_local`, so `010-pam-sudo-touchid` edits `/etc/pam.d/sudo` directly there and has to be re-run after an OS update (`chezmoi state delete-bucket --bucket=scriptState && chezmoi apply`). When upstream demotes another tuple (next expected: Sequoia 15 on Apple Silicon, September 2027 or later), add it to the table with a new era block; the comments in `brew-tiers.toml` say what to record.

## Bootstrapping a host older than Ventura

chezmoi is a Go program, and every August a Go release drops the oldest macOS it supports. A chezmoi built with a too-new Go does not start on the older release: the dynamic linker dies on a Security.framework symbol the OS does not have (on Big Sur, `_SecTrustCopyCertificateChain`, which is macOS 12 API). The `get.chezmoi.io` script installs the newest release by default, so on these hosts pass the tag of the last release built before the relevant Go cutoff:

| macOS | Go cutoff | chezmoi tag |
| --- | --- | --- |
| 12 Monterey | Go 1.27 (August 2026) requires 13 | `-t v2.72.0` |
| 11 Big Sur | Go 1.25 (August 2025) requires 12 | `-t v2.64.0` |
| 10.15 Catalina | Go 1.23 (August 2024) requires 11 | `-t v2.52.0` |
| 10.14 Mojave | Go 1.21 (August 2023) requires 10.15 | `-t v2.37.0` |

These are the last releases before each Go version shipped. The toolchain a given binary was built with is not recorded in the release, so if one still fails to start, step back one more release. Once brew is up, the era's pinned `chezmoi` formula is the durable replacement, since its bottle was built for that OS.

`bw` needs no special handling: it is brew's `bitwarden-cli`, installed by the first apply from the era's core checkout, so it is whatever version that era had (a 2021 build on Mojave). Whether a very old client still talks to the current server is not verified here.

## MacPorts

`.chezmoiscripts/00-macos/016-macports` installs the MacPorts CLI (`port`) from the official per-release installer package, latest version, into `/opt/local`. Brew remains the package manager; MacPorts is the fallback for Intel Macs once brew stops running on them (scheduled for September 2027), and on the era-pinned hosts `017-macports-packages` installs the few ports that stand in for formulae the era's homebrew-core checkout does not have and that have a prebuilt MacPorts archive for that Darwin version: retry, sshpass and uv on Big Sur and older, and fastfetch, pam-reattach and wasm-tools on Mojave. On a Tier 1 host that list is empty. The same inline era conditionals in the brew lists say which entries MacPorts covers. `.commonprofile` puts `/opt/local/bin` and `/opt/local/sbin` ahead of brew's directories on `PATH`, so an installed port wins a collision. The installer's own edits to `~/.zprofile` and `~/.bash_profile` are undone by the next apply, since both files are managed here. MacPorts updates itself with `sudo port selfupdate`.
