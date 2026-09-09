# Agent notes for this repo

Operational conventions for any agent working in this chezmoi source directory. Not deployed to `$HOME` (see `.chezmoiignore.tmpl`).

## Shell snippets given to the user

- Never use `read -p "prompt" var`. Use a separate `read -rs var` line (see conversation history for the exact pattern) -- `-p` breaks in this user's interactive session.
- Never use `chezmoi apply --verbose` in commands given to the user to run themselves -- it's broken in interactive sessions. Plain `chezmoi apply` is fine.
