# direnv: per-directory environment, loaded on cd.
#
# Replaces 10-autowatch.zsh, which hooked chpwd to `source` and then `eval` a
# .watchrc out of whatever directory you had just entered. Any repository
# cloned under ~/repositories could therefore run arbitrary code the moment you
# cd'd into it, with no approval step and nothing to review -- the file was
# sourced before you ever saw it. direnv covers the same "set things up when I
# enter this project" use case, but refuses to load an .envrc until it has been
# approved with `direnv allow` in that directory, and revokes that approval
# automatically whenever the file's contents change.
#
# Note that direnv is not a drop-in replacement for what the watcher did with
# WATCH_CMD: it manages environment variables, it does not supervise a
# long-running background process. For a file watcher, run one in the
# foreground in its own terminal, or give the project a real systemd --user
# unit. Backgrounding a process from a shell hook is what made the old one
# both dangerous and hard to reason about -- it leaked PIDs across cds.
#
# Guarded on the binary existing: the package lists install direnv from
# apt/dnf/brew, but this file is applied to hosts where the package step may
# not have run yet, and an unguarded hook would emit command-not-found on
# every new shell.
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi
