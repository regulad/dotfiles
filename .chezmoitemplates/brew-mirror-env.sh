{{- /* Bottle-mirror environment for an era-pinned brew. Included by
       posix-preamble.sh and dot_commonprofile.tmpl inside their era block as
         template "brew-mirror-env.sh" (dict "era" <era name> "mirror" .brewMirror)
       and renders to nothing for an era whose brew cannot use it. The
       credentials come from .chezmoidata/brew-mirror.toml; the reasoning is
       in docs/homebrew-older-macos.md, "Bottle mirror".

       Mojave is left out on purpose, twice over: its brew 3.2.17 has no
       HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN (Bearer only, and the proxy
       accepts nothing but this account's Basic auth), and it applies
       HOMEBREW_ARTIFACT_DOMAIN to every download URL, not just ghcr.io
       ones, without ever falling back to the original, so with it set no
       source tarball or cask could be fetched at all. From 3.6.6 on the
       Basic token exists and only ghcr.io bottle (and portable-ruby) URLs
       are rewritten. */ -}}
{{- if and .era (ne .era "mojave") -}}
# Bottles come through the Nexus proxy of ghcr.io (.chezmoidata/brew-mirror.toml)
# with the read-only account as Basic auth. Once this is set brew has no
# working fallback to ghcr.io on any era, so if the mirror is down:
#   env -u HOMEBREW_ARTIFACT_DOMAIN brew install ...
# (unset, not empty: an empty value breaks the URL rewrite on 3.x/4.x).
export HOMEBREW_ARTIFACT_DOMAIN="{{ .mirror.artifact_domain }}"
export HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN="{{ printf "%s:%s" .mirror.user .mirror.password | b64enc }}"
{{- end -}}
