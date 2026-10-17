# Tooling providers

The Linux and macOS `070-js-tooling` and `100-python-tooling` hooks render the
shared `js-tooling.sh` and `python-tooling.sh` templates. Homebrew supplies
equivalent packaged tools; uv and pnpm supply tools absent from the host's
snapshot, disabled there, or requiring a particular version, fork or extras.
The `110-rust-tooling` and `120-go-tooling` hooks likewise share
`rust-tooling.sh` and `go-tooling.sh`. The existing macOS-only `osc52pty`
install remains conditional in the shared Go template.
Windows retains its own package-manager choices.

Every pinned era attempts the remaining language-manager installs, including
Cargo and Go. Vencord and VS Code extensions are attempted on non-headless
machines too. These attempts can expose an upstream OS or compiler requirement;
the hooks report failures instead of silently skipping the entire tool set.

## Python runtimes

`.chezmoidata/tooling.toml` records explicit versioned formulae. Both the native
and Rosetta package lists use the appropriate era, without probing installed
binaries while rendering templates:

| Homebrew era | Python formulae |
| --- | --- |
| Mainline, including Linux | `python@3.15`, `python@3.14` |
| Catalina | `python@3.10` |
| Big Sur | `python@3.11` |
| Monterey | `python@3.12` |
| Ventura | `python@3.13` |
| Sonoma / current Intel | `python@3.14` |

The remaining 3.14 tools receive `$(brew --prefix python@3.14)/bin/python3.14`
where that formula exists. This prevents uv from choosing Rosetta's Python on
Apple Silicon or Fedora's interpreter without development headers.

On snapshots before 3.14, `017-macports-packages` supplies `python314` and the
tooling script selects `/opt/local/bin/python3.14`. It also supplies `python313`
through Monterey and `python312` through Big Sur for the existing RenderCV and
Frida runtime requirements. MacPorts uv is used through Monterey: it is absent
from the two oldest core snapshots, and Monterey's uv 0.1.21 predates `uv tool`.
The installer explicitly invokes that uv even if an older Homebrew uv remains.
MacPorts publishes [uv](https://packages.macports.org/uv/) and
[Python 3.14](https://packages.macports.org/python314/) builds for older macOS.

## Provider audit, 2026-10-17

The audit inspected Homebrew/core's Git trees and formula definitions at every
`core_commit` in `.chezmoidata/brew-tiers.toml`, plus mainline and the Vercel
cask. A name match alone does not establish equivalent functionality.

| Tool previously installed through uv or pnpm | Provider |
| --- | --- |
| Ruff | `ruff` formula; uv on Catalina, where it is absent |
| ty | `ty` formula on mainline and the 2026 pins; uv on earlier pins |
| pre-commit | `pre-commit` formula on every era |
| ansible-core | `ansible` formula, which includes ansible-core, on every era |
| ansible-lint, yamllint, OCI CLI | `ansible-lint`, `yamllint`, `oci-cli` formulae on every era |
| Poetry, Hatch, autopep8 | Homebrew on Linux and macOS |
| Mermaid CLI | `mermaid-cli`; pnpm on Big Sur (disabled formula) and Monterey (absent) |
| Vercel | `vercel-cli` on older pins, `vercel` formula on Sonoma, `vercel` CLI cask on mainline Linux/macOS |
| Cline | `cline` formula on the 2026 pins and mainline through macOS 26; pnpm on earlier snapshots and macOS 27 |
| TypeScript and language servers, Bitwarden CLI | Existing Homebrew providers; Catalina uses pnpm for the missing TypeScript language server |
| Wrangler | `cloudflare-wrangler` on Ventura and later pins/mainline; pnpm on older pins whose formula is the legacy v1 CLI |
| go-ios, Cloudflare cf | pnpm; no equivalent core formula (`cf` is an unrelated timestamp filter) |
| keydive, mangadex-downloader, pymobiledevice3, claude-swap, patatt | uv; no matching core formula |
| yt-dlp | uv to preserve its pinned extras and `bgutil-ytdlp-pot-provider` |
| keymap-renderer | uv to preserve the `regulad/keymap-renderer` fork |
| Frida | uv with `frida==16.7.0`, `frida-tools==13.7.1`, matching the roothide device server |
| RenderCV | uv with `rendercv[full]@2.2` to preserve the schema, plus the existing dependency caps |

Cline's formula is frozen at 3.0.3, deprecated, and scheduled for disablement on
2027-05-18. Mainline explicitly excludes macOS 27, so that host uses pnpm.
Revisit the provider when the formula becomes disabled. Vercel's current
[CLI cask](https://formulae.brew.sh/cask/vercel) supports Linux as well as macOS;
it is unrelated to GUI-only cask gating.

Homebrew's Mermaid formula omits Puppeteer's browser download. The hook runs
the formula's bundled Puppeteer installer (`install.mjs`, or `install.js` on
older releases) before removing the pnpm copy, preserving diagram rendering.
That download uses Puppeteer's normal user cache and is reused on later applies.

Pinned Brew snapshots keep their existing formula versions. That can mean an
older CLI and, for newly selected formulae, a source build when a suitable
bottle is unavailable. These changes do not move the Homebrew pins.

## Migration and verification

After installing the selected Homebrew replacements, the hooks remove only
their matching uv/pnpm global packages. This prevents user-local executables
from continuing to shadow Homebrew. Frida, RenderCV, yt-dlp and other retained
packages are not removed. A failed Homebrew install stops before cleanup.

Run `python tools/test-tooling.py` with chezmoi and Bash available. On Windows,
pass Git Bash using `--bash C:/Users/<user>/scoop/apps/git/current/bin/bash.exe`.
The checks render every configured era plus current macOS/Linux, check shell
syntax and provider choices, and run mocked migrations, including failure and
repeat-apply cases. They install no packages and do not apply host dotfiles.
They do not prove that current registry packages run on every older OS; the
macOS and Docker apply workflows provide the real installation checks.
