{{- /* Loads one macOS brew into an interactive shell; included by
       dot_commonprofile.tmpl, indented to fit. Called with a dict:
         prefix -- the brew prefix (/opt/homebrew, /usr/local)
         pin    -- its [brewTiers.legacy] row, or an empty dict for Tier 1
         label  -- "<series>/<arch>", for the comment
       Apple Silicon up to Tahoe 26 renders it twice, once for the native
       brew and once for the Rosetta one in /usr/local (docs/rosetta-brew.md);
       everywhere else once. */ -}}
eval "$({{ .prefix }}/bin/brew shellenv)"
{{- if .pin }}
# macOS {{ .label }} is era-pinned to brew {{ .pin.brew_tag }}
# (see .chezmoidata/brew-tiers.toml); keep it there. The env stops the
# implicit update; the wrapper stops the explicit one, since `brew update`
# would move brew and both taps off the era and, on 10.x, leave a brew
# that will not start. `brew!` is the unwrapped binary for when you mean
# it (the next `chezmoi apply` re-pins). Functions and aliases only exist
# in interactive shells; the hookscripts never run `brew update`.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_FROM_API=1
{{- with includeTemplate "brew-era-env.sh" (dict "era" .pin.era) }}{{ . | nindent 0 }}{{ end }}
brew() {
    if [ "$1" = "update" ]; then
        echo "WARNING: this brew is pinned! run \`brew! update\` to update anyway" >&2
        echo "(the pinned checkouts are single-commit: brew, homebrew/core and homebrew/cask each need \`git fetch --unshallow\` first)" >&2
        return 1
    fi
    command brew "$@"
}
alias brew!='command brew'
{{- end }}
