# Attempt the source installs on pinned hosts too; failures propagate.
# The list is .chezmoidata/cargo-tools.toml, shared with 00-nt/550-cargo.
{{- range .cargoTools.crates }}
{{-   $os := get . "os" }}
{{-   if or (not $os) (has $.chezmoi.os $os) }}
cargo install --locked {{ .name }}
{{-   end }}
{{- end }}
