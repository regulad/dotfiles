{{- /* Extra brew environment for an era-pinned host, beyond the pin itself.
       Included by posix-preamble.sh and dot_commonprofile.tmpl inside their
       era block as
         template "brew-era-env.sh" (dict "era" <era name>)
       and renders only what the era needs. Reasoning in
       docs/homebrew-older-macos.md ("Other caveats"). The bottle mirror is
       not here: every host gets that, from brew-mirror-env.sh.

       Brewed curl. Apple's trust store on Catalina through Monterey predates
       roots that current download hosts chain to (emSign Root CA - G1 first
       shipped in the macOS 13 store), so the system curl brew runs cannot
       verify them. And on Catalina and Big Sur the system curl cannot reach
       the bottle mirror at all: Apple's curl defaults to its bundled
       LibreSSL backend (have_openssl() in Apple's vtls.c patch;
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
{{- if has .era (list "catalina" "bigsur" "monterey") -}}
# This release's Apple trust store predates roots that download hosts now
# chain to (emSign, via InCommon, since July 2026), and on 10.15/11 Apple's
# curl speaks TLS 1.2 at most (LibreSSL 2.8.3), which the mirror refuses, so
# brew downloads through its own curl (openssl@3, TLS 1.3, Mozilla bundle)
# once the curl formula is installed.
export HOMEBREW_FORCE_BREWED_CURL=1
{{- end -}}
