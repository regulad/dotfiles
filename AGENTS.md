# Agent notes for this repo

Operational conventions for any agent working in this chezmoi source directory. Not deployed to `$HOME` (see `.chezmoiignore.tmpl`).

## Applying changes

- After changing a file in this source directory, if the current system is chezmoi-managed, you may run a scoped apply for just that file: `chezmoi apply <target-path>` (e.g. `chezmoi apply "$env:USERPROFILE\.config\vlc\vlcrc"`). This avoids rendering unrelated templates -- a full `chezmoi apply` requires the Bitwarden vault to be unlocked, which only the user can do.
- Scripts can be scoped too, addressed by their *stripped* target name (no `run_*_` prefix, no `.tmpl` suffix), which lives under the destination dir: `chezmoi apply "$env:USERPROFILE\.chezmoiscripts\00-nt\230-projectm-presets.cmd"`. Run-once state is recorded normally. Do NOT pipe such a command through `Select-Object -First N`: pipeline stopping kills chezmoi before it records script state.

## Shell snippets given to the user

- Never use `read -p "prompt" var`. Use a separate `read -rs var` line (see conversation history for the exact pattern) -- `-p` breaks in this user's interactive session.
- Never use `chezmoi apply --verbose` in commands given to the user to run themselves -- it's broken in interactive sessions. Plain `chezmoi apply` is fine.
