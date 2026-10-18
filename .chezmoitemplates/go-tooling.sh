# Fedora defaults GOTOOLCHAIN=local. Allow Go to fetch a newer toolchain
# when a tool requires one, including on era-pinned Macs.
export GOTOOLCHAIN=auto
# The list is .chezmoidata/go-tools.toml, shared with 00-nt/560-go-tooling.
{{- range .goTools.packages }}
{{-   $os := get . "os" }}
{{-   if or (not $os) (has $.chezmoi.os $os) }}
go install {{ .module }}
{{-   end }}
{{- end }}
