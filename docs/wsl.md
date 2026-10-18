# WSL: `wsl-deploy`, `wsl-enter` and `wsl-update`

Three Windows-side helpers in `~/.local/bin`, exposed to `cmd` by doskey macros in `.doskey.mac`. They invoke by full path on purpose: `~/.local/bin` is only put on `PATH` by `.commonprofile`, which is POSIX shells only.

`wsl-deploy [fedora|ubuntu]` installs the newest built image as `regulad-<flavor>`:

```console
wsl-deploy                    # newest ubuntu image for this architecture
wsl-deploy fedora
wsl-deploy.ps1 -SetDefault    # and make it what a bare `wsl` starts
```

It finds the newest unexpired `wsl-<flavor>-<arch>` artifact, downloads it to `~\Downloads` with a progress readout, and imports it to `%LOCALAPPDATA%\wsl\regulad-<flavor>`. The `.wsl` is deleted afterwards unless `-KeepDownload` is passed. Notable behaviour:

- **It is destructive.** If `regulad-<flavor>` already exists, continuing *unregisters* it — the VHD and everything in it is gone, with no undo. It prompts first; `-Force` skips the prompt. The unregister waits until the new image has fully downloaded, so a failed or interrupted download leaves the old instance intact.
- Every image carries the commit it was built from in `/etc/dotfiles-commit`, written by the overlay step of `.github/workflows/wsl-package.yml` and checked against the run's commit before upload. `wsl-deploy` reads it back from an installed instance (`wsl -d regulad-<flavor> -u root --exec cat /etc/dotfiles-commit`, no login shell, no OOBE) to say whether it is already the newest build or behind one; nothing in WSL tracks this on its own. Images built before the file existed report "unknown". (`wsl-deploy` used to keep this in a `deployed-from.json` beside the VHD; that is gone, and a leftover copy is inert.)
- Afterwards it offers, y/N, to make the instance the default distribution — worth taking, since the default is otherwise whatever was installed first (on older setups, Docker Desktop's `docker-desktop` distro).
- Images are published as Actions artifacts rather than release assets because they are ~5 GB against a 2 GB release-asset cap. Artifacts expire after 14 days, so if none is found, push to `master` or re-run the Docker workflow.
- Unless `-NoLaunch` is passed, the import opens a shell, which is what triggers `/etc/oobe.sh`. That reads the Bitwarden API credentials from the Windows host's own `%USERPROFILE%\.secrets\.bwrc` over DrvFs and runs the privileged apply; it will ask for the vault master password. To re-run it later: `wsl -d regulad-<flavor> -u root -- /etc/oobe.sh`.

`wsl-enter [fedora|ubuntu]` opens a shell in an already-deployed instance, in the directory you called it from:

```console
D:\repositories\foo> wsl-enter        # lands in /mnt/d/repositories/foo
```

It installs nothing and destroys nothing. Where the current directory is something WSL cannot see — a UNC path, a mapped network drive, or a non-filesystem PowerShell provider like `HKLM:` — it starts at `$HOME` and says so, rather than failing the launch and leaving you with no shell. `-NoCd` always starts at `$HOME`.

`wsl-update [fedora|ubuntu]` brings an installed instance's dotfiles up to HEAD of the chezmoi source on the Windows side, without redeploying:

```console
wsl-update                    # ubuntu: patch to HEAD, then a full apply
wsl-update fedora
wsl-update.ps1 -DryRun        # show the patch and check it applies; change nothing
wsl-update.ps1 -NoApply       # patch and re-init now, apply later
```

An instance's chezmoi source is a plain copy of the tree its image was built from (a git repository with no commits), and `/etc/dotfiles-commit` names that commit. `wsl-update` reads the file the way `wsl-deploy` does, builds the patch from that commit to HEAD with git on the Windows side (fetching first if the image's commit is not in the clone), checks it with `git apply --check` inside the instance and applies it. It then writes HEAD to `/etc/dotfiles-commit`, re-renders the chezmoi config with `chezmoi init`, keeping the instance's `useDummySecrets` as it is (`useHeadless` is always off in WSL), and runs the full `chezmoi apply`, interactively, since it may ask for the Bitwarden master password. Notable behaviour:

- **The commit is recorded before the apply**, as soon as the patch is in, because the file says what the source tree is. If the apply fails, running `wsl-update` again finds nothing to patch and retries the apply.
- **Only HEAD travels.** Uncommitted changes on the Windows side are left out, with a note.
- **A patch that does not apply changes nothing**: `git apply` is all or nothing, and the check runs first. That happens when the instance's source was edited where the patch touches it.
- **HEAD behind or beside the instance's commit** (a rollback, a diverged branch) still works, since the patch makes the instance's tree HEAD's, but that undoes whatever the instance has that HEAD lacks, so it asks first; `-Force` skips the question.
- The patch is written by git itself (`--output`), never through PowerShell's pipeline, so the binary hunks for the age-encrypted files survive, and it is built with CRLF conversion, textconv and external diff tools off and `a/`/`b/` prefixes fixed, whatever the local git config says.
