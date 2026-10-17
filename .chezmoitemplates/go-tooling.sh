# Fedora defaults GOTOOLCHAIN=local. Allow Go to fetch a newer toolchain
# when a tool requires one, including on era-pinned Macs.
export GOTOOLCHAIN=auto
go install mvdan.cc/sh/v3/cmd/shfmt@latest
go install golang.org/x/tools/gopls@latest
go install golang.org/x/tools/cmd/goimports@latest
go install honnef.co/go/tools/cmd/staticcheck@latest
go install github.com/twpayne/find-duplicates@latest
go install github.com/swaggo/swag/cmd/swag@latest
{{- if eq .chezmoi.os "darwin" }}
go install github.com/roy2220/osc52pty@master
{{- end }}
