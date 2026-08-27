# Vim plugin bootstrap, shared verbatim by the linux and macos hooks. The
# Windows half is .chezmoiscripts/00-nt/run_onchange_after_805-vim-plugins.cmd,
# which does the same three things and carries the same caveats.
#
# Two separate reasons this cannot live inside ~/.vimrc:
#
#  1. The vimrc opens with `call vundle#begin()`, which is a hard E117 on a
#     machine where Vundle has never been cloned -- and Vundle is the thing
#     that would have cloned it. `colorscheme darcula` a few lines later is an
#     E185 for the same reason. Vim then stops on a "Press ENTER" prompt at
#     every single launch.
#
#  2. coc.nvim needs more than a clone. Vundle understands exactly three plugin
#     options -- 'rtp', 'name' and 'pinned', see :h vundle-plugins-configure --
#     with no 'branch' and no build hook anywhere in its installer, so the
#     {'branch': 'release', 'do': 'npm ci'} that coc used to be declared with
#     was parsed, merged into the bundle dict, and then never read by anything.
#     Vundle cloned coc's default branch, which ships TypeScript sources and no
#     build/index.js, and coc refused to start. The release branch carries the
#     prebuilt bundle, so pin it here.
#
# Vundle hardcodes $HOME/.vim/bundle as its bundle dir on every platform
# (autoload/vundle.vim), so that is the tree these clones go into -- notably
# still .vim, not vimfiles, on Windows.

VUNDLE_URI="https://github.com/VundleVim/Vundle.vim.git"
COC_URI="https://github.com/neoclide/coc.nvim.git"
BUNDLE_DIR="$HOME/.vim/bundle"
COC_EXTENSIONS_FILE="$HOME/.coc-extensions.txt"

if ! command -v vim &>/dev/null; then
	echo "note: vim is not installed, skipping vim plugin bootstrap" >&2
	exit 0
fi

# Clone <uri> at <branch> into <dir>, or move an existing checkout onto that
# branch. The set-branches/reset path is what repairs a coc.nvim that an older
# apply -- or a bare :PluginInstall run before this script existed -- left
# sitting on the unbuilt default branch, which a plain `git pull` would not.
sync_repo() {
	local uri="$1" dir="$2" branch="$3"
	if [ -d "$dir/.git" ]; then
		git -C "$dir" remote set-url origin "$uri"
		# --single-branch clones restrict the fetch refspec, so widen it before
		# fetching or origin/$branch never materialises for the checkout below.
		git -C "$dir" remote set-branches origin "$branch"
		git -C "$dir" fetch -q origin "$branch"
		git -C "$dir" checkout -q -B "$branch" "origin/$branch"
	else
		git clone -q --branch "$branch" --single-branch "$uri" "$dir"
	fi
}

mkdir -p "$BUNDLE_DIR"
sync_repo "$VUNDLE_URI" "$BUNDLE_DIR/Vundle.vim" master
sync_repo "$COC_URI" "$BUNDLE_DIR/coc.nvim" release

# Vundle owns the rest of the Plugin list in ~/.vimrc. Plain :PluginInstall (no
# bang) clones what is missing and returns 'todate' for anything already on
# disk without touching it -- which is exactly what keeps the coc.nvim pin
# above from being dragged back onto the default branch.
#
# -E -s (silent ex mode) rather than the `vim +PluginInstall +qall` Vundle's
# README suggests: in a normal-mode headless Vim the startup "Press ENTER"
# prompt swallows the queued -c commands and nothing at all gets installed.
# Vundle exits non-zero out of ex mode even when every clone succeeded, so the
# result is judged by what landed on disk rather than by $?.
echo "note: installing vim plugins with Vundle" >&2
vim -E -s -N -u "$HOME/.vimrc" -c 'PluginInstall' -c 'qall!' </dev/null >/dev/null || true

for required in Vundle.vim coc.nvim darcula; do
	[ -d "$BUNDLE_DIR/$required" ] || echo "warning: $required missing from $BUNDLE_DIR after :PluginInstall" >&2
done

# coc.nvim without extensions loads and does nothing: the extensions are the
# language servers. They are npm packages that coc installs through its own
# node host, so no node means no point going further.
if ! command -v node &>/dev/null; then
	echo "warning: node not found, so coc.nvim has no extension host; skipping :CocInstall" >&2
	exit 0
fi

# Bail rather than carry on with an empty list. mapfile over a missing file is
# not an error -- it just yields zero entries -- and zero entries here means the
# prune below reads "nothing is wanted" and uninstalls every extension coc has.
if [ ! -f "$COC_EXTENSIONS_FILE" ]; then
	echo "error: $COC_EXTENSIONS_FILE is missing; refusing to prune coc extensions against an empty list" >&2
	exit 1
fi

# strip \r: the list picks up CRLF line endings on Windows checkouts
# (core.autocrlf), and a trailing \r turns every entry into a package name npm
# has never heard of -- the same trap 160-install-vscode-ext.sh documents.
mapfile -t wanted < <(tr -d '\r' <"$COC_EXTENSIONS_FILE" | sed '/^[[:space:]]*$/d')

if [ "${#wanted[@]}" -gt 0 ]; then
	# -sync so the download completes before Vim exits; :CocInstall is
	# otherwise fire-and-forget and qall! would kill it mid-flight.
	echo "note: installing coc extensions: ${wanted[*]}" >&2
	vim -E -s -N -u "$HOME/.vimrc" -c "CocInstall -sync ${wanted[*]}" -c 'qall!' </dev/null >/dev/null
fi

# Uninstall anything coc is carrying that the list no longer asks for, so
# dot_coc-extensions.txt is the whole truth rather than an append-only wishlist
# -- same contract as dot_vscode-extensions.txt.
#
# This is done by hand rather than with :CocUninstall because coc has no
# headless uninstall at all. All three routes were tried against this checkout:
# :CocUninstall is CocActionAsync, so qall! kills it mid-flight; CocAction()
# refuses to run until the node host sets g:coc_service_initialized, which it
# only ever does in an interactive session; and the raw
# coc#rpc#request('uninstallExtension', ...) underneath it errors for the same
# reason. (:CocInstall -sync is fine -- coc#rpc#ready() is 1 headless, it is
# just the initialized flag that never flips.)
#
# So do exactly what coc's own uninstallExtensions does in build/index.js:
# delete the module directory and drop the dependency entry. coc rebuilds its
# extension set from this package.json on the next start.
#
# Path mirrors coc#util#get_data_home() in autoload/coc/util.vim: $XDG_CONFIG_HOME/coc
# when that variable points at a real directory, ~/.config/coc otherwise.
if [ -n "${XDG_CONFIG_HOME:-}" ] && [ -d "${XDG_CONFIG_HOME:-}" ]; then
	COC_DATA_HOME="$XDG_CONFIG_HOME/coc"
else
	COC_DATA_HOME="$HOME/.config/coc"
fi
COC_PKG="$COC_DATA_HOME/extensions/package.json"

if [ -f "$COC_PKG" ]; then
	is_wanted() {
		local candidate="$1" w
		for w in "${wanted[@]}"; do
			[ "$w" = "$candidate" ] && return 0
		done
		return 1
	}
	mapfile -t installed < <(node -e 'process.stdout.write(Object.keys(require(process.argv[1]).dependencies||{}).join("\n"))' "$COC_PKG")
	unwanted=()
	for extension in "${installed[@]}"; do
		[ -n "$extension" ] || continue
		is_wanted "$extension" || unwanted+=("$extension")
	done
	if [ "${#unwanted[@]}" -gt 0 ]; then
		echo "note: removing unlisted coc extensions: ${unwanted[*]}" >&2
		for extension in "${unwanted[@]}"; do
			rm -rf "$COC_DATA_HOME/extensions/node_modules/$extension"
		done
		node -e "var fs=require('fs'),p=process.argv[1],j=JSON.parse(fs.readFileSync(p,'utf8'));process.argv.slice(2).forEach(function(k){delete j.dependencies[k]});fs.writeFileSync(p,JSON.stringify(j,null,2)+'\n');" "$COC_PKG" "${unwanted[@]}"
	fi
fi
