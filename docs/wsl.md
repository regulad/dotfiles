# WSL: `wsl-deploy` and `wsl-enter`

Two Windows-side helpers in `~/.local/bin`, exposed to `cmd` by doskey macros in `.doskey.mac`. They invoke by full path on purpose: `~/.local/bin` is only put on `PATH` by `.commonprofile`, which is POSIX shells only.

`wsl-deploy [fedora|ubuntu]` installs the newest built image as `regulad-<flavor>`:

```console
wsl-deploy                    # newest ubuntu image for this architecture
wsl-deploy fedora
wsl-deploy.ps1 -SetDefault    # and make it what a bare `wsl` starts
```

It finds the newest unexpired `wsl-<flavor>-<arch>` artifact, downloads it with a progress readout, and imports it to `%LOCALAPPDATA%\wsl\regulad-<flavor>`. Notable behaviour:

- **It is destructive.** If `regulad-<flavor>` already exists, continuing *unregisters* it — the VHD and everything in it is gone, with no undo. It prompts first; `-Force` skips the prompt.
- Each import records its provenance in `deployed-from.json` next to the VHD before opening the interactive shell, so later runs can tell you whether the installed instance is already the newest build or is behind one. Nothing in WSL tracks this on its own. The file lives in the install directory precisely so `wsl --unregister` takes it with the instance rather than leaving a stale claim behind.
- Afterwards it offers, y/N, to make the instance the default distribution — worth taking, since the default is otherwise whatever was installed first (on older setups, Docker Desktop's `docker-desktop` distro).
- Images are published as Actions artifacts rather than release assets because they are ~5 GB against a 2 GB release-asset cap. Artifacts expire after 14 days, so if none is found, push to `master` or re-run the Docker workflow.
- Unless `-NoLaunch` is passed, the import opens a shell, which is what triggers `/etc/oobe.sh`. That reads the Bitwarden API credentials from the Windows host's own `%USERPROFILE%\.secrets\.bwrc` over DrvFs and runs the privileged apply; it will ask for the vault master password. To re-run it later: `wsl -d regulad-<flavor> -u root -- /etc/oobe.sh`.

`wsl-enter [fedora|ubuntu]` opens a shell in an already-deployed instance, in the directory you called it from:

```console
D:\repositories\foo> wsl-enter        # lands in /mnt/d/repositories/foo
```

It installs nothing and destroys nothing. Where the current directory is something WSL cannot see — a UNC path, a mapped network drive, or a non-filesystem PowerShell provider like `HKLM:` — it starts at `$HOME` and says so, rather than failing the launch and leaving you with no shell. `-NoCd` always starts at `$HOME`.
