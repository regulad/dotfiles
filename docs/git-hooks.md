# Git hooks

`init.templateDir` points at `~/.config/git/template` on every host, so every `git init` and `git clone` copies its hooks into the new repository's `.git/hooks`:

| Hook | Does | Comes from |
|---|---|---|
| `pre-commit` | runs [pre-commit](https://pre-commit.com) in a repository with a `.pre-commit-config.yaml` | `pre-commit init-templatedir`, from a hookscript, on every host |
| `sendemail-validate` | signs `git send-email` patches with patatt ([git send-email](git-send-email.md)) | `dot_config/git/template`, with real secrets only |

A repository that predates a hook gets it from `git init` inside it, which only adds what is missing and never replaces a hook that is already there. The loop in [git send-email](git-send-email.md#signing) does every repository under `~/repositories` at once.

## pre-commit

The hook is pre-commit's own. `00-{linux,macos}/101-pre-commit-templatedir` (sharing `.chezmoitemplates/pre-commit-templatedir.sh`) and `00-nt/502-pre-commit-templatedir` run `pre-commit init-templatedir --hook-type pre-commit ~/.config/git/template` on every apply, after the python-tooling scripts install pre-commit: brew's formula on macOS and Linux, a uv tool on Windows. That way the hook follows pre-commit's template as it changes. Each host writes its own copy, because the hook has the absolute path of pre-commit's Python written into it. On brew hosts that path is under `opt/`, which survives upgrades. On Windows the file has CRLF line endings, which Git for Windows runs fine.

- **No `.pre-commit-config.yaml`:** pre-commit says it is skipping, and the commit goes ahead.
- **Not installed:** with neither its interpreter path nor `pre-commit` on `PATH` working, the hook stops every commit, in any repository. `git commit --no-verify` gets past it.
- **`pre-commit install`** in a repository replaces the copy with its per-repository hook, as usual. It recognises the copy as its own by its `# ID:` line, so it keeps no `pre-commit.legacy`.
