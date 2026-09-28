{{ template "posix-preamble.sh" . }}
# Homebrew installer, shared verbatim by 00-macos/005-homebrew.sh and
# 00-linux/005-homebrew.sh. This used to live in posix-preamble.sh, which
# every hookscript inlines -- so whichever script chezmoi happened to run first
# on a brew-less host did the installing, and the installer's own environment
# (pinned refs, launchctl PATH) had nowhere to live. Now it is one script that
# runs before anything that includes posix-preamble-brew.sh, and it is a
# run_after_ rather than run_once_ so a host whose brew was removed gets it
# back on the next apply.
#
# Two modes, decided by .chezmoidata/brew-tiers.toml via the preamble:
#
#  mainline  (BREW_ERA_PINNED=0): the current upstream installer, current
#            brew, formulae from the JSON API. Every Linux host and every macOS
#            that mainline Homebrew still ships bottles for.
#
#  era-pinned (BREW_ERA_PINNED=1): a macOS that upstream has demoted to
#            source-only. Mainline brew would still *run* there, but without
#            bottles every `brew install` is a from-source build that may not
#            succeed. The bottles built while that OS was supported are still
#            on ghcr.io, so brew is laid down here BY HAND -- no upstream
#            installer: none of them pins a ref (they reset to the moving
#            branch or the newest tag), all of them end with `brew update`,
#            and the older ones clone homebrew-core from a branch that no
#            longer exists. What the installer does is small and stable, and
#            is reproduced below: the prefix directories with their
#            ownership, a git clone of Homebrew/brew checked out at the last
#            release that treated this OS as fully supported, and the Intel
#            bin/brew symlink (the Command Line Tools are 003-macos-prereqs'
#            job on every Mac, pinned or not). Then
#            homebrew/core and homebrew/cask are tapped through that brew and
#            checked out at the era's commit for each. From then on
#            HOMEBREW_NO_AUTO_UPDATE keeps brew from moving itself and
#            HOMEBREW_NO_INSTALL_FROM_API makes it read those local taps
#            instead of the API, which only describes today's bottles. The
#            preamble exports both for every hookscript; .commonprofile does
#            it for interactive shells and turns `brew update` into a warning.
#
# Sudo is required: brew lives under /opt/homebrew, /usr/local or
# /home/linuxbrew, all of which need root to create. There is no rootless
# mode -- Homebrew's own is unsupported, and it used to be a source of
# half-working hosts here.

if [ "$(uname -o)" != "Darwin" ] && [ "$(uname -o)" != "GNU/Linux" ]; then
	echo "note: not Darwin or GNU/Linux, nothing to install" >&2
	exit 0
fi

if [ "$IS_ATOMIC" -eq 1 ] && ! load_brew; then
	# Bluefin lays brew down itself, via brew-setup.service on first boot, into
	# the same /var/home/linuxbrew prefix the upstream installer would use.
	# Running the installer here would race that unit. 022-brew-packages.sh
	# refuses with a pointer to `systemctl status brew-setup.service` if it
	# still hasn't landed by the time packages are due.
	echo "note: atomic host, leaving brew to brew-setup.service" >&2
	exit 0
fi

# The brew git repo, found WITHOUT running brew: the layout is fixed -- the
# prefix itself on Apple Silicon, $prefix/Homebrew on Intel and Linux -- and
# a brew invocation is not always possible (a stray `brew update` on a 10.x
# host leaves a checkout that refuses to start there).
brew_repo_path() {
	if [ "$(uname -o)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
		printf '%s\n' "$CHEZMOI_HOMEBREW_PREFIX"
	else
		printf '%s\n' "$CHEZMOI_HOMEBREW_PREFIX/Homebrew"
	fi
}

# Two halves, because of what sits between them. The brew repo is pinned
# with git alone, by path; only then is brew loaded and asked to pin the
# taps.
pin_brew_repo() {
	[ "$BREW_ERA_PINNED" -eq 1 ] || return 0
	local repo have
	repo="$(brew_repo_path)"
	have="$(git -C "$repo" describe --tags --exact-match 2>/dev/null || true)"
	if [ "$have" != "$BREW_PIN_TAG" ]; then
		echo "note: pinning brew to $BREW_PIN_TAG (was ${have:-untagged})" >&2
		git -C "$repo" fetch --quiet --tags origin
		git -C "$repo" checkout --quiet "$BREW_PIN_TAG"
	fi
}

pin_brew_taps() {
	[ "$BREW_ERA_PINNED" -eq 1 ] || return 0
	# Full git taps are required for HOMEBREW_NO_INSTALL_FROM_API. Old brew
	# clones them on `brew tap`; shallow clones are refused, so this is a
	# gigabyte or so the first time. Each tap then goes to its era commit.
	pin_tap homebrew/core "$BREW_ERA_CORE_COMMIT"
	pin_tap homebrew/cask "$BREW_ERA_CASK_COMMIT"
}

pin_tap() {
	local tapname="$1" want="$2" tap
	if ! brew tap | grep -qx "$tapname"; then
		echo "note: cloning $tapname (full history, this takes a while)" >&2
		brew tap "$tapname"
	fi
	tap="$(brew --repository "$tapname")"
	if ! git -C "$tap" cat-file -e "$want^{commit}" 2>/dev/null; then
		# A clone made before the table was bumped; fetch the commit by hash.
		git -C "$tap" fetch --quiet origin "$want"
	fi
	if [ "$(git -C "$tap" rev-parse HEAD)" != "$want" ]; then
		echo "note: pinning $tapname to ${want:0:8} (era $BREW_ERA_NAME)" >&2
		git -C "$tap" checkout --quiet "$want"
	fi
}

# Homebrew by hand, for an era-pinned macOS. Mirrors what install.sh does
# for the same prefix, minus the parts that move: the directory set and its
# user:admin ownership, the repo, the Intel symlink, the cache dir. The
# Command Line Tools are 003-macos-prereqs' job and are already in place.
install_brew_pinned() {
	local prefix="$CHEZMOI_HOMEBREW_PREFIX" repo user d
	repo="$(brew_repo_path)"
	user="$(id -un)"

	# The directories install.sh creates under the prefix. On Apple Silicon
	# the prefix is new and wholly ours; on Intel it is /usr/local, which
	# other things also use, so only these entries are created and chowned,
	# never the prefix recursively -- same as upstream.
	local dirs="bin etc include lib sbin share opt var Frameworks
		etc/bash_completion.d lib/pkgconfig share/aclocal share/doc share/info
		share/locale share/man share/man/man1 share/man/man2 share/man/man3
		share/man/man4 share/man/man5 share/man/man6 share/man/man7
		share/man/man8 var/log var/homebrew var/homebrew/linked
		Cellar Caskroom"
	echo "note: creating $prefix layout (owner $user:admin)" >&2
	sudo mkdir -p "$prefix"
	if [ "$repo" = "$prefix" ]; then
		# Apple Silicon: the whole of /opt/homebrew is the repo and is ours.
		sudo chown "$user:admin" "$prefix"
		sudo chmod ug=rwx "$prefix"
	fi
	for d in $dirs; do
		if [ ! -d "$prefix/$d" ]; then
			sudo mkdir -p "$prefix/$d"
			sudo chown "$user:admin" "$prefix/$d"
		fi
		sudo chmod ug=rwx "$prefix/$d"
	done
	# zsh refuses completion dirs that are group/other writable.
	for d in share/zsh share/zsh/site-functions; do
		sudo mkdir -p "$prefix/$d"
		sudo chown "$user:admin" "$prefix/$d"
		sudo chmod go-w "$prefix/$d"
	done
	mkdir -p "$HOME/Library/Caches/Homebrew"

	# The repo: init + fetch, not clone, because on Apple Silicon the repo
	# directory is the prefix and already has entries in it.
	if [ ! -d "$repo/.git" ]; then
		echo "note: fetching Homebrew/brew into $repo" >&2
		sudo mkdir -p "$repo"
		sudo chown "$user:admin" "$repo"
		git -C "$repo" init --quiet
		git -C "$repo" config remote.origin.url https://github.com/Homebrew/brew
		git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
		git -C "$repo" config core.autocrlf false
		git -C "$repo" config --bool core.symlinks true
		git -C "$repo" fetch --quiet --force origin
		git -C "$repo" fetch --quiet --force --tags origin
	fi
	pin_brew_repo

	# Intel: brew lives in $prefix/Homebrew and is reached via a symlink.
	if [ "$repo" != "$prefix" ]; then
		ln -sf ../Homebrew/bin/brew "$prefix/bin/brew"
	fi
}

# Already installed? Re-verify the pin on every apply: the repo first, with
# git alone, then the taps through the (now correct) brew.
if [ -x "$(brew_repo_path)/bin/brew" ]; then
	pin_brew_repo
	if ! load_brew; then
		echo "error: brew is present under $CHEZMOI_HOMEBREW_PREFIX but 'brew shellenv' failed" >&2
		exit 1
	fi
	echo "note: brew already installed at $HOMEBREW_PREFIX" >&2
	pin_brew_taps
	exit 0
fi

require_sudo "005-homebrew (installing brew)"
echo "note: installing brew into $CHEZMOI_HOMEBREW_PREFIX" >&2

if [ "$BREW_ERA_PINNED" -eq 1 ]; then
	if [ "$(uname -o)" != "Darwin" ]; then
		echo "error: era pins are macOS-only, but this Linux host has one" >&2
		exit 1
	fi
	install_brew_pinned
else
	# The official installer asks for sudo itself; NONINTERACTIVE skips the
	# "press RETURN" prompt only. It would install the Command Line Tools
	# too, but 003-macos-prereqs has already done that, so it finds them.
	NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [ "$(uname -o)" = "Darwin" ]; then
	# launchd-started processes (GUI apps, `brew services`) don't read the
	# shell profile; give them the prefix on PATH. /usr/local/bin is in the
	# default already, so this only adds anything on Apple Silicon, but
	# setting it on Intel too is harmless and keeps one code path.
	if [ "$CHEZMOI_HOMEBREW_PREFIX" = "/usr/local" ]; then
		launchd_path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
	else
		launchd_path="$CHEZMOI_HOMEBREW_PREFIX/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
	fi
	sudo launchctl config user path "$launchd_path"
	sudo launchctl config system path "$launchd_path"
fi

if ! load_brew; then
	echo "error: brew install finished but no brew found under $CHEZMOI_HOMEBREW_PREFIX (or any fallback)" >&2
	exit 1
fi
pin_brew_taps
echo "note: brew $(brew --version | head -n1) ready at $HOMEBREW_PREFIX" >&2
