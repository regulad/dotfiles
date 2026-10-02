# Containers

No host runs Docker Desktop. Each one gets the native engine it can run, and the knobs live in [`.chezmoidata/containers.toml`](../.chezmoidata/containers.toml).

| Host | Engine | Docker Engine API | Installed / started by |
| --- | --- | --- | --- |
| Windows | `wslc` (WSL 3.0.1+) | none on the Windows side | `00-nt/115-wsl-update` |
| macOS 26+, Apple silicon | Apple's `container` | partial, via socktainer | `00-macos/020-brew-packages`, `035-container-runtime` |
| macOS 10.15–26 otherwise (Intel; Apple silicon up to 15) | colima (dockerd in a Lima VM) | full | `00-macos/020-brew-packages`, `035-container-runtime` |
| macOS 10.14 Mojave | none | -- | -- |
| Linux, WSL distros | podman (`podman.socket`) | podman's compat API | `00-linux` package lists, `150-user-services` |

## Windows: wslc

`wslc` ships with WSL from 3.0.1 (stable since 2026-09-29). It runs containerd and dockerd inside a per-user VM and exposes its own CLI (`wslc run`, `wslc build`, `wslc image ...`). `115-wsl-update` runs `wsl --update` on every apply, then fails with `error:` if WSL is still older than `wslMinVersion` or `wslc.exe` is missing. `wsl --update` installs GitHub's latest release and cannot be pinned, so the repo checks the floor rather than fetching a particular release.

- `wslc` is not on the PATH of a shell opened before the update. It lives in `C:\Program Files\WSL\`.
- Its settings are `%LOCALAPPDATA%\wslc\settings.yaml` (`wslc settings`), not `.wslconfig`.
- **Shortfall:** the dockerd stays inside wslc's VM. Windows gets no Docker Engine socket or pipe ([microsoft/WSL#40976](https://github.com/microsoft/WSL/issues/40976)), and wslc has no compose ([#40948](https://github.com/microsoft/WSL/issues/40948)). So `act` (dropped from scoop), testcontainers, `docker compose` and compose-based devcontainers have nothing to target on Windows. Single-container Dev Containers and the VS Code Containers extension support wslc directly. See the README TODOs.

## macOS: apple/container or colima

The split is `appleMinMacos`. Apple supports `container` on macOS 26 only, on Apple silicon only. It starts on 15, but containers cannot reach each other and `container network` is missing. The `container` and `socktainer` formulae both require arm64 and Tahoe.

- **apple/container hosts** run `container` and [socktainer](https://github.com/socktainer/socktainer) as brew services. socktainer serves a partial Docker Engine API, enough for the docker CLI, compose, buildx, Dev Containers and testcontainers in most cases. `035` installs container's recommended Linux kernel once, since the service starts it with `--disable-kernel-install`.
- **colima hosts** run colima as a brew service, using `vz` from Ventura on and QEMU before it. On the Catalina and Big Sur pins, colima predates its service block, so `035` starts the VM directly and it is not restarted at login. The VM defaults to 2 CPUs and 2 GiB; change that with `colima start --edit`.
- Both get the docker CLI, compose, buildx and `docker-credential-helper` from brew. `~/.docker/config.json` is merged by chezmoi: `credsStore` is `osxkeychain`, and `cliPluginsExtraDirs` points at the brew plugin directory. `035` creates and selects a docker context (`socktainer` or `colima`) for GUI apps. `.commonprofile` exports `DOCKER_HOST` at the same socket for tools that ignore contexts.
- podman is no longer installed on macOS: there it is only a client for a `podman machine` VM, and its client speaks podman's libpod API, which neither engine serves. Earlier installs are left alone, because the package lists are install-only.

## Docker Desktop removal

Both platforms remove Docker Desktop once, with its containers, images and volumes:

- `00-nt/105-docker-desktop-remove` (Windows) runs the uninstaller through `sudo` (one UAC prompt). It also unregisters the `docker-desktop` distros, deletes the leftover directories from [Docker's uninstall doc](https://docs.docker.com/desktop/uninstall/) including `~/.docker`, and uninstalls scoop's `act`. It runs before `115`, because WSL 3.0.1 is reported to break Docker Desktop ([microsoft/WSL#41759](https://github.com/microsoft/WSL/issues/41759)).
- `00-macos/019-docker-desktop-remove` (macOS) runs `Docker.app/Contents/MacOS/uninstall` and drops the `docker-desktop`/`docker` cask. It deletes the leftovers and any dangling links into the app (CLI links, `/var/run/docker.sock`). It runs before `020`, so the docker formulae can link. `035` removes the stale `desktop-linux` context.

## Known upstream issues (2026-10)

- WSL 3.0.1: [#41739](https://github.com/microsoft/WSL/issues/41739) makes `binfmt_misc` read-only, so `systemd-binfmt` can fail in distros (compare `00-linux/004-wsl-binfmt-interop`).
- apple/container on macOS 27: [#2275](https://github.com/apple/container/issues/2275) (every command hangs when `pfd` is unresponsive) and [#2335](https://github.com/apple/container/issues/2335) (starting a container can break host IPv4).
- socktainer: compose re-runs with `platform:` ([#399](https://github.com/socktainer/socktainer/issues/399)) and recreate ([#385](https://github.com/socktainer/socktainer/issues/385)).
