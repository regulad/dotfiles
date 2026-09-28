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

## Shell snippets given to the user

- Never use `read -p "prompt" var`. Use a separate `read -rs var` line (see conversation history for the exact pattern) -- `-p` breaks in this user's interactive session.
- Never use `chezmoi apply --verbose` in commands given to the user to run themselves -- it's broken in interactive sessions. Plain `chezmoi apply` is fine.
