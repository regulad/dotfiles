# Agent notes for this repo

Operational conventions for any agent working in this chezmoi source directory. Not deployed to `$HOME` (see `.chezmoiignore.tmpl`).

## Worktrees

- Keep worktrees outside the chezmoi source directory, for example in sibling `../chezmoi-worktrees/`. Chezmoi loads `.chezmoitemplates` and `.chezmoidata` from nested worktrees too, even under `.claude/`, before applying `.chezmoiignore`; their older copies can silently override the main source's templates and data. Verify changes using the main source after moving any nested worktrees with `git worktree move`.

## Applying changes

- After changing a file in this source directory, if the current system is chezmoi-managed, you may run a scoped apply for just that file: `chezmoi apply <target-path>` (e.g. `chezmoi apply "$env:USERPROFILE\.config\vlc\vlcrc"`). This avoids rendering unrelated templates -- a full `chezmoi apply` requires the Bitwarden vault to be unlocked, which only the user can do.
- Scripts can be scoped too, addressed by their *stripped* target name (no `run_*_` prefix, no `.tmpl` suffix), which lives under the destination dir: `chezmoi apply "$env:USERPROFILE\.chezmoiscripts\00-nt\230-projectm-presets.cmd"`. Run-once state is recorded normally. Do NOT pipe such a command through `Select-Object -First N`: pipeline stopping kills chezmoi before it records script state.

## WSL instances

- A running WSL instance (`regulad-fedora`, `regulad-ubuntu`) is updated only by the user, interactively, with `wsl-update <flavor>` from Windows (`dot_local/bin/wsl-update.ps1`). It patches the instance's own chezmoi source from the commit in its `/etc/dotfiles-commit` to this clone's committed HEAD, records that commit there, re-renders the chezmoi config and runs the full `chezmoi apply`, which can ask for the Bitwarden master password. The scoped applies above are for the system you run on, not for the instances on it. Never update one yourself, scoped or not: no `chezmoi apply` inside it, no `chezmoi --source /mnt/c/...` pointed at the Windows working tree, and no edits to its chezmoi source, its persistent state or `/etc/dotfiles-commit`. Each of those leaves the instance in a state its recorded commit does not describe. Reading is fine (files, logs, `chezmoi diff`, `cat`, `managed`, `execute-template`). To get a change into an instance, commit it and ask the user to run `wsl-update`, which takes committed work only, pushed or not. This was done once with `chezmoi --source`, on 2026-10-22.

## Template gates

- Never gate a file's template on whether a tool the hookscripts install is present yet (`lookPath`, `stat`, `output`, `env` probing for it). chezmoi applies files before `run_after_` scripts, and every package install here is one, so on a fresh machine the probe sees the pre-install state: the file renders wrong on its first apply and only corrects itself on the next, and it flips back on any apply where the tool is off PATH. Gate on the data the installing script itself branches on (`.chezmoi.os`, `.useDummySecrets`, the `.chezmoidata` tables such as the brew era) and point the two at each other in comments. Example: `dot_gitconfig.tmpl` turns on patatt signing from `.brewTiers.legacy`, the lookup `00-macos/100-python-tooling` uses to decide whether it installs patatt, not from `lookPath "patatt"`. This has been proposed more than once.

## Headless gates

- Anything GUI-only that a hookscript installs or configures goes behind `.useHeadless`, as a whole script in `.chezmoiignore.tmpl`'s Head block or as `{{ if not .useHeadless }}` around its entry in a package list; see "Headless hosts" in `docs/hookscripts.md`. WSL is always headful; don't special-case it.

## POSIX hookscripts

- A new `.chezmoiscripts/00-{macos,linux}` script opens with `{{ template "posix-preamble-brew.sh" . }}` if its job needs brew (or `$HOMEBREW_PREFIX`), else `{{ template "posix-preamble.sh" . }}`. Never hardcode `/opt/homebrew`: hookscripts use `$HOMEBREW_PREFIX`, static config templates use `{{ .homebrewPrefix }}`. Use `brew_trust` rather than `brew trust`. See `docs/hookscripts.md` and `docs/homebrew-older-macos.md`. Longer documentation goes in `docs/` (chezmoi-ignored), linked from README.md; keep README.md to the overview and install steps.

## Commits

- Every commit an LLM assisted with carries a well-formed `Co-Authored-By` trailer on its own line at the end of the message: the model's name exactly as its own system prompt states it, and its vendor's no-reply address. One trailer per assisting model. The two in use here:

  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Co-authored-by: Codex <noreply@openai.com>
  ```

  Other Claude models follow the same shape with their own name (`Claude Opus 5`, `Claude Sonnet 5`, ...). `git commit --trailer '<the line>'` adds it without hand-editing the message. Commits are GPG-signed by the user's config; do not bypass that. A commit that went in without the trailer is rewritten with `git commit --amend --no-edit --trailer ...` (and cherry-pick plus amend for anything below the tip) and force-pushed with `--force-with-lease`, never a bare `--force`.
- A commit that cannot change what CI checks (documentation, this file) starts its subject with `[no ci]`, which GitHub Actions skips: a push to `master` otherwise starts all three workflows, Docker's WSL packaging included.

## CI after a push

- After pushing, attach to every workflow run the push started and wait for them: `gh run list --commit <sha>` finds them, and `gh run watch <id> --exit-status --compact` follows each in the background. They take from about 45 minutes (macOS) to well over an hour (Docker). Report each run to the user as it returns, not all of them at the end.
- When one fails, read the failing job's log (`gh run view <id> --job <job-id> --log-failed`) and find the cause before saying anything about it. Then tell the user what failed and whether the change caused it or something outside it did: an upstream outage, a flaky network, a runner image. Compare the previous run of the same workflow before calling a failure either way. Propose the fix, and commit and push it only once the user agrees, then attach to the runs that push starts. Keep going, one returning run at a time, until everything is green or the user calls it. Do not re-run a job or push a fix on your own: each push starts the whole matrix again.

## Hookscript messages

- Every line a hookscript prints to the user carries one of four prefixes, on every platform (`echo ... >&2`, `echo ... 1>&2`, `Write-Host`): `debug:` for progress and idempotency chatter (installing X, already present, up to date, entering the script); `notice:` for a decision or a result the user should register (skipping something and why, wrote or deployed a file, the shell was changed, a follow-up they must do); `warning:` for something that is off but not fatal (a fallback taken, a service not up yet, a missing profile); `error:` right before a non-zero exit. There is no `note:`.

## Portability of shell code

- Everything under `.chezmoiscripts/00-{macos,linux}`, `.chezmoitemplates/*.sh` and the dotfiles sourced by shells runs on macOS `/bin/bash` 3.2 and BSD userland as far back as macOS 10.15, as well as GNU. Detect the platform with `uname -s` (`Darwin`/`Linux`), never `uname -o` (BSD only grew it in macOS 13; before that the substitution is empty and the test silently fails). `uname -o 2>/dev/null` is acceptable only for the Android check. No bash 4 features (`declare -A`, `${var,,}`, `mapfile`/`readarray` -- use a `while IFS= read -r` loop, `|&`), no `sed -i` without an argument, no `readlink -f`, `date -d`, `stat -c` or `sort -V` outside Linux-only branches.

## Shell snippets given to the user

- Never use `read -p "prompt" var`. Use a separate `read -rs var` line (see conversation history for the exact pattern) -- `-p` breaks in this user's interactive session.
- Never use `chezmoi apply --verbose` in commands given to the user to run themselves -- it's broken in interactive sessions. Plain `chezmoi apply` is fine.
