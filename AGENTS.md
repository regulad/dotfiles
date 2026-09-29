# Agent notes for this repo

Operational conventions for any agent working in this chezmoi source directory. Not deployed to `$HOME` (see `.chezmoiignore.tmpl`).

## Applying changes

- After changing a file in this source directory, if the current system is chezmoi-managed, you may run a scoped apply for just that file: `chezmoi apply <target-path>` (e.g. `chezmoi apply "$env:USERPROFILE\.config\vlc\vlcrc"`). This avoids rendering unrelated templates -- a full `chezmoi apply` requires the Bitwarden vault to be unlocked, which only the user can do.
- Scripts can be scoped too, addressed by their *stripped* target name (no `run_*_` prefix, no `.tmpl` suffix), which lives under the destination dir: `chezmoi apply "$env:USERPROFILE\.chezmoiscripts\00-nt\230-projectm-presets.cmd"`. Run-once state is recorded normally. Do NOT pipe such a command through `Select-Object -First N`: pipeline stopping kills chezmoi before it records script state.

## POSIX hookscripts

- A new `.chezmoiscripts/00-{macos,linux}` script opens with `{{ template "posix-preamble-brew.sh" . }}` if its job needs brew (or `$HOMEBREW_PREFIX`), else `{{ template "posix-preamble.sh" . }}`. Never hardcode `/opt/homebrew`: hookscripts use `$HOMEBREW_PREFIX`, static config templates use `{{ .homebrewPrefix }}`. Use `brew_trust` rather than `brew trust`. See `docs/hookscripts.md` and `docs/homebrew-older-macos.md`. Longer documentation goes in `docs/` (chezmoi-ignored), linked from README.md; keep README.md to the overview and install steps.

## Commits

- Every commit an LLM assisted with carries a well-formed `Co-Authored-By` trailer on its own line at the end of the message: the model's name exactly as its own system prompt states it, and its vendor's no-reply address. One trailer per assisting model. The two in use here:

  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Co-authored-by: Codex <noreply@openai.com>
  ```

  Other Claude models follow the same shape with their own name (`Claude Opus 5`, `Claude Sonnet 5`, ...). `git commit --trailer '<the line>'` adds it without hand-editing the message. Commits are GPG-signed by the user's config; do not bypass that. A commit that went in without the trailer is rewritten with `git commit --amend --no-edit --trailer ...` (and cherry-pick plus amend for anything below the tip) and force-pushed with `--force-with-lease`, never a bare `--force`.

## Hookscript messages

- Every line a hookscript prints to the user carries one of four prefixes, on every platform (`echo ... >&2`, `echo ... 1>&2`, `Write-Host`): `debug:` for progress and idempotency chatter (installing X, already present, up to date, entering the script); `notice:` for a decision or a result the user should register (skipping something and why, wrote or deployed a file, the shell was changed, a follow-up they must do); `warning:` for something that is off but not fatal (a fallback taken, a service not up yet, a missing profile); `error:` right before a non-zero exit. There is no `note:`.

## Portability of shell code

- Everything under `.chezmoiscripts/00-{macos,linux}`, `.chezmoitemplates/*.sh` and the dotfiles sourced by shells runs on macOS `/bin/bash` 3.2 and BSD userland as far back as macOS 10.14, as well as GNU. Detect the platform with `uname -s` (`Darwin`/`Linux`), never `uname -o` (BSD only grew it in macOS 13; before that the substitution is empty and the test silently fails). `uname -o 2>/dev/null` is acceptable only for the Android check. No bash 4 features (`declare -A`, `${var,,}`, `mapfile`/`readarray` -- use a `while IFS= read -r` loop, `|&`), no `sed -i` without an argument, no `readlink -f`, `date -d`, `stat -c` or `sort -V` outside Linux-only branches.

## Shell snippets given to the user

- Never use `read -p "prompt" var`. Use a separate `read -rs var` line (see conversation history for the exact pattern) -- `-p` breaks in this user's interactive session.
- Never use `chezmoi apply --verbose` in commands given to the user to run themselves -- it's broken in interactive sessions. Plain `chezmoi apply` is fine.
