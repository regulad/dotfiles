{{- /* The bottle mirror, for every host that runs brew: mainline and
       era-pinned macOS alike, and Linux. Included at the top level of
       posix-preamble.sh and dot_commonprofile.tmpl as
         template "brew-mirror-env.sh" .brewMirror
       with the account from .chezmoidata/brew-mirror.toml. Reasoning, and
       what each pinned brew does with the pair, in docs/brew-mirror.md.

       The one exception is a GitHub-hosted Actions runner, and it has to be
       decided when this runs, not when chezmoi renders it: the container
       images and WSL tarballs are built on such a runner and ship the
       rendered .commonprofile, and the machine they end up on is not one.
       RUNNER_ENVIRONMENT is GitHub's own variable ("github-hosted" or
       "self-hosted"); the Docker builds and the WSL chroot do not inherit
       the runner's environment, so docker-publish.yml and wsl-package.yml
       hand it through explicitly. */ -}}
# Bottles and portable-ruby come through the Nexus proxy of ghcr.io, with its
# read-only account as Basic auth -- except on a GitHub-hosted Actions runner,
# which fetches from ghcr.io itself. brew's fallback to ghcr.io carries the
# same Basic header, which ghcr.io refuses, so if the mirror is down:
#   env -u HOMEBREW_ARTIFACT_DOMAIN -u HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN brew install ...
# (unset, not empty: an empty domain breaks the URL rewrite on brew 3.x/4.x).
if [ "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]; then
    export HOMEBREW_ARTIFACT_DOMAIN="{{ .artifact_domain }}"
    export HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN="{{ printf "%s:%s" .user .password | b64enc }}"
fi
