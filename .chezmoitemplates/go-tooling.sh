# Fedora defaults GOTOOLCHAIN=local. Allow Go to fetch a newer toolchain
# when a tool requires one, including on era-pinned Macs.
export GOTOOLCHAIN=auto
# The list is .chezmoidata/go-tools.toml, shared with 00-nt/560-go-tooling.
# Each install fetches from the module proxy and checks the checksum database,
# either of which has the occasional bad minute (sum.golang.org's TLS handshake
# timed out on a macOS runner, 2026-10-18), so it gets three tries, 10 and 30
# seconds apart. retry replays stdin on each try; go install wants none.
{{- range .goTools.packages }}
{{-   $os := get . "os" }}
{{-   if or (not $os) (has $.chezmoi.os $os) }}
retry -t 3 -d 10,30 -- go install {{ .module }} </dev/null
{{-   end }}
{{- end }}
