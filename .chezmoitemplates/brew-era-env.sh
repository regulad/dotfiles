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

       2. Brewed curl. Apple's trust store on Mojave through Monterey
       predates roots that current download hosts chain to (emSign Root CA -
       G1 first shipped in the macOS 13 store), so the system curl brew runs
       cannot verify them. And on Catalina and Big Sur the system curl
       cannot reach the bottle mirror at all: Apple's curl defaults to its
       bundled LibreSSL backend (have_openssl() in Apple's vtls.c patch;
       SecureTransport only with CURL_SSL_BACKEND=secure-transport), those
       releases ship LibreSSL 2.8.3, which tops out at TLS 1.2, and the
       mirror sits behind Cloudflare with a TLS 1.3 minimum ("tlsv1 alert
       protocol version"). brew's lighter switch for the trust-store problem,
       HOMEBREW_FORCE_BREWED_CA_CERTIFICATES, cannot help with that.
       HOMEBREW_FORCE_BREWED_CURL is the other switch brew has for an
       unusable system curl: once the curl formula is installed, brew runs
       every download through it -- openssl@3, TLS 1.3, and the ca-certificates
       bundle as its default trust store -- which fixes both. Before it is
       installed brew falls back to the system curl on its own, so
       020-brew-packages installs curl first on these eras, with the mirror
       variables unset for that one install: ghcr.io still takes TLS 1.2 and
       its chain is in Apple's store. */ -}}
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
# chain to (emSign, via InCommon, since July 2026), and on 10.15/11 Apple's
# curl speaks TLS 1.2 at most (LibreSSL 2.8.3), which the mirror refuses, so
# brew downloads through its own curl (openssl@3, TLS 1.3, Mozilla bundle)
# once the curl formula is installed.
export HOMEBREW_FORCE_BREWED_CURL=1
{{- end -}}
