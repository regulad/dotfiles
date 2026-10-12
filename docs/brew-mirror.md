# Bottle mirror

Every brew this repo runs fetches its bottles through a Sonatype Nexus docker (proxy) repository of ghcr.io at `repo.regulad.xyz`, logged in with a read-only account. The URL and the account are in `.chezmoidata/brew-mirror.toml`, committed in the clear on purpose: otherwise a first apply could not install a single bottle until Bitwarden is unlocked, and `bw` itself comes from brew. Nexus proxies manifests and blobs by digest byte-for-byte (verified against ghcr.io, including tags from the 2021 pins and a portable-ruby blob). It keeps a copy of everything that passes through, so a bottle any host has installed exists somewhere other than GitHub. That matters most for the era-pinned Macs ([Homebrew on older macOS](homebrew-older-macos.md)), whose bottles are old blobs that GitHub is not obliged to keep.

## How it is set

`.chezmoitemplates/brew-mirror-env.sh` points brew at one of two sources and switches to the other when the first is not answering (see [Fallback](#fallback)). For the mirror it exports `HOMEBREW_ARTIFACT_DOMAIN`, the repository URL, and `HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN`, the account as `user:password`, base64-encoded. For ghcr.io it unsets both. `posix-preamble.sh` includes it at top level for every hookscript, before brew is first loaded. `.commonprofile` includes it at top level for login shells. Both cover macOS (mainline and era-pinned) and Linux, WSL and the container images included. The layout is the Docker Registry v2 one that brew already speaks. `HOMEBREW_ARTIFACT_DOMAIN` replaces `https://ghcr.io` in the bottle URL, and the rest of the path (`/v2/homebrew/core/<formula>/manifests/<version>`, then `/blobs/sha256:...`) is what Nexus expects under `/repository/ghcr-io`, so no URL rewriting is needed on either side.

## Where it is not used

- **GitHub-hosted Actions runners**, which start on ghcr.io instead and fall back to the mirror. The template checks `RUNNER_ENVIRONMENT` (GitHub's own variable, `github-hosted` or `self-hosted`) when it runs. On ghcr.io a runner authenticates with its own token, handed to the apply as `DOTFILES_GITHUB_TOKEN`: anonymous pulls count against a limit that every job on the runner's IP shares. ghcr.io takes a GitHub token as `Authorization: Bearer <base64(token)>` (the raw token gets a 403, Basic auth a 401), which is what brew sends for `HOMEBREW_DOCKER_REGISTRY_TOKEN`, so the template sets that to the token's base64. The check has to happen at run time. The container images and WSL tarballs are built on such a runner and ship the rendered `.commonprofile`, but the machine they end up on is not a runner, so they use the mirror there. A runner's environment does not reach the places the builds run brew, so it is handed through explicitly. `docker-publish.yml` passes `RUNNER_ENVIRONMENT=github-hosted` as a build-arg (github-builder only builds on GitHub-hosted runners, and a reusable workflow's `with:` has no `runner` context). Each Dockerfile declares it as an `ARG` and keeps it through `su -l -w` into the apply. `wsl-package.yml` keeps the runner's own value through `sudo env` and `runuser -l -w`. A self-hosted runner uses the mirror.
- **The first curl install on Catalina, Big Sur and Monterey.** `020-brew-packages` unsets both variables for that one `brew install curl`, because the system curl it still runs through cannot reach the mirror. See "Other caveats" in [Homebrew on older macOS](homebrew-older-macos.md).
- **The Dockerfiles' bootstrap.** The upstream installer and `brew install chezmoi` run before chezmoi has rendered anything, so they always use ghcr.io, authenticated with the runner's token as above when the build has it (the `GIT_AUTH_TOKEN` BuildKit secret). In CI that is the intended behaviour. A local `docker build` gets it too, anonymously.
- **Anything that is not a ghcr.io bottle.** Only bottle URLs and portable-ruby are rewritten. Casks, source tarballs and the git fetches of brew and its taps go to their own hosts. On Linux, brew 7 also tries `<domain>/Homebrew/glibc-bootstrap/...` for glibc-bootstrap before github.com, which Nexus answers with a 404. That download only happens on a host with a glibc older than brew's minimum, which none of the supported distros has.
- **Shells that never read `.commonprofile`**, such as a non-login `ssh host brew ...`. Those get brew's defaults.

## What each brew does with the pair

From each brew's source at its tag (the era pins in `.chezmoidata/brew-tiers.toml`, and mainline):

| brew | rewrites | auth sent to the mirror | falls back to ghcr.io |
| --- | --- | --- | --- |
| 3.6.6, 4.1.12 | ghcr.io bottle and portable-ruby URLs | always; Basic from the token above | no |
| 4.3.20, 4.6.10 | same | 4.3.20 always; 4.6.10 only when a token is set | no (only github.com source URLs fall back) |
| 6.0.x | same, and tolerates a domain that already ends in `/v2` | only when a token is set; `none` disables it | tries ghcr.io second, but with the same header, which ghcr.io rejects |
| 7.0.x (mainline, 7.0.7 read) | same as 6.0.x, plus glibc-bootstrap on Linux (see above) | same as 6.0.x | same as 6.0.x |

So no brew in use falls back on its own: the old ones never try ghcr.io, and the new ones try it with the mirror's Basic header, which ghcr.io refuses (401). Nor can any of them try ghcr.io first and the mirror second, which is what a runner wants. Hence the fallback below, which switches the credentials along with the host.

## Fallback

`brew-mirror-env.sh` decides the source per command, not per machine:

- **Which source first.** The mirror on every host, ghcr.io on a GitHub-hosted runner. The other is the fallback.
- **Asking.** The mirror is up when its registry root (`<domain>/v2/`) returns 200 to the account; ghcr.io is up when its root returns 401, which it says to anyone and which costs no token. Each probe gives up after 5 seconds, and on the era Macs it uses brew's own curl, as brew does there (Apple's on Catalina and Big Sur cannot reach the TLS 1.3-only mirror).
- **When.** Only where bottles are about to be fetched: in the `brew` wrapper for `install`, `reinstall`, `upgrade`, `fetch` and `bundle`; at the top of every script on `posix-preamble-brew.sh`; and in `005-homebrew` before it installs brew (portable-ruby is a bottle). The pick goes to `~/.cache/dotfiles/brew-source` and stands for ten minutes, so an apply asks once, and a source that was down is asked again ten minutes later. Anything else gets the last pick, or the first source, with no round trip, which keeps login shells off the network.
- **Retrying.** When one of those commands fails, the wrapper retries it once from the other source, if that one answers, with a `warning:`. That covers a source that dies partway through an apply, or one bottle the mirror cannot serve.
- **Switching.** To the mirror: both variables above, plus `HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1` so brew 6+ does not make its own doomed retry on ghcr.io, and `HOMEBREW_DOCKER_REGISTRY_TOKEN` unset, since brew would prefer it to the Basic token and the mirror takes nothing but Basic. To ghcr.io: all three unset, never set to empty (brew 3.x/4.x test the domain variable for presence, not content, and an empty one rewrites the URL to `/v2/...`), and `HOMEBREW_DOCKER_REGISTRY_TOKEN` set from `DOTFILES_GITHUB_TOKEN` where there is one.

The wrapper is a `brew` function: `posix-preamble.sh` defines it for hookscripts once `HAS_BREW` is known (a function named `brew` would satisfy `command -v brew` whether or not brew is installed), and `.commonprofile` for interactive shells, where an era-pinned Mac's `brew update` guard (`brew-profile-env.sh`) calls it too. `brew!` on those Macs, and anything that runs the brew binary by path, still sees a source but gets no fallback.

By hand, the ghcr.io half of the switch is:

```sh
env -u HOMEBREW_ARTIFACT_DOMAIN -u HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN -u HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK brew install ...
```

Mojave's brew 3.2.17 is why Mojave is no longer supported. It has no Basic auth, only Bearer via `HOMEBREW_DOCKER_REGISTRY_TOKEN`, and the proxy accepts nothing but this account's Basic auth. Anonymous access is off, the Docker bearer-token realm is not enabled, and brew's built-in anonymous `Authorization: Bearer QQ==` for ghcr.io gets a 401. It also applies `HOMEBREW_ARTIFACT_DOMAIN` to every download URL with no fallback, so with the variable set it could not fetch any source tarball or cask either.

## Nexus configuration

One Nexus setting matters. Homebrew's bottle indexes carry no top-level `mediaType` (the OCI spec makes it optional; the `homebrew/brew` image index has one), and the docker proxy's foreign-layer detection dereferences it. With *foreign layer caching* enabled, every bottle manifest request 500s with a `NullPointerException` in `DockerProxyFacetSupport.identifyForeignLayers`, while child manifests and blobs by digest still work. This is Sonatype's NEXUS-22498, reported against 3.19 in January 2020, and the workaround is the one they gave then: foreign layer caching is off on the `ghcr-io` repository. Bottle layers are not foreign layers, so nothing is lost. The bug is still present in 3.70.4.

The mirror sits behind Cloudflare with a TLS 1.3 minimum. Every client in use speaks TLS 1.3 except Apple's system curl on Catalina and Big Sur, which is what the brewed-curl switch in `brew-era-env.sh` is for.
