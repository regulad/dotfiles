{{- /* Extra brew environment for an era-pinned host, beyond the pin itself.
       Included by posix-preamble.sh and dot_commonprofile.tmpl inside their
       era block as
         template "brew-era-env.sh" (dict "era" <era name> "mirror" .brewMirror)
       and renders only the parts the era needs. Reasoning for both parts is
       in docs/homebrew-older-macos.md ("Bottle mirror" and "Other caveats").

       1. Bottle mirror. The credentials come from .chezmoidata/brew-mirror.toml.
       Mojave is left out on purpose, twice over: its brew 3.2.17 has no
       HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN (Bearer only, and the proxy
       accepts nothing but this account's Basic auth), and it applies
       HOMEBREW_ARTIFACT_DOMAIN to every download URL, not just ghcr.io
       ones, without ever falling back to the original, so with it set no
       source tarball or cask could be fetched at all. From 3.6.6 on the
       Basic token exists and only ghcr.io bottle (and portable-ruby) URLs
       are rewritten.

       2. CA bundle. Apple's trust store on Mojave through Monterey predates
       roots that current download hosts chain to (emSign Root CA - G1 first
       shipped in the macOS 13 store), so the system curl brew runs cannot
       verify them. HOMEBREW_FORCE_BREWED_CA_CERTIFICATES is brew's own
       switch for a too-old system store -- it flips on by itself below
       10.15.6 -- and makes the curl shim pass brew's Mozilla bundle as
       --cacert once the ca-certificates formula is installed
       (020-brew-packages installs it first on these eras). Harmless before
       that: brew only exports SSL_CERT_FILE when the file exists. */ -}}
{{- if and .era (ne .era "mojave") -}}
# Bottles come through the Nexus proxy of ghcr.io (.chezmoidata/brew-mirror.toml)
# with the read-only account as Basic auth. Once this is set brew has no
# working fallback to ghcr.io on any era, so if the mirror is down:
#   env -u HOMEBREW_ARTIFACT_DOMAIN brew install ...
# (unset, not empty: an empty value breaks the URL rewrite on 3.x/4.x).
export HOMEBREW_ARTIFACT_DOMAIN="{{ .mirror.artifact_domain }}"
export HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN="{{ printf "%s:%s" .mirror.user .mirror.password | b64enc }}"
{{- end }}
{{- if has .era (list "mojave" "catalina" "bigsur" "monterey") }}
# This release's Apple trust store predates roots that download hosts now
# chain to (emSign, via InCommon, since July 2026), so brew's curl verifies
# against brew's own Mozilla bundle instead, once ca-certificates is installed.
export HOMEBREW_FORCE_BREWED_CA_CERTIFICATES=1
{{- end -}}
