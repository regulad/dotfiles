# Theos, the iOS/tvOS tweak + application toolchain, shared verbatim by the
# linux and macos hooks. https://theos.dev/docs/installation-linux
#
# Upstream's whole install story is one script, bin/install-theos, and it is
# the only supported entry point -- it owns the dependency lists, the fakeroot
# alternative, the toolchain tarball URLs and the SDK fetch, all of which move
# independently of the docs. So this defers to it rather than reimplementing
# it, and confines itself to the three things the installer gets wrong for a
# chezmoi-managed account:
#
#  1. $THEOS. Left unset, install-theos picks a shell rc by hand -- ~/.bashrc,
#     or ~/.zshenv under zsh -- and appends `export THEOS=~/theos` to it. Both
#     of those files are managed here, so the edit is reverted by the next
#     apply and re-appended by the one after, forever. Exporting THEOS before
#     calling the installer takes that branch away entirely: set_theos() opens
#     with "$THEOS is already set ... Nothing to do here." The durable half of
#     the same setting lives in .commonprofile.
#
#  2. Prompts. The Linux path asks, interactively, whether the toolchain should
#     support Swift -- and an apply is frequently not attached to a terminal.
#     $CI is the installer's own escape hatch for that (`if [[ -z $CI ]]`), and
#     it answers no, i.e. the smaller L1ghtmann iOSToolchain rather than the
#     Swift 5.8/Ubuntu 20.04 one. To switch later: remove
#     $THEOS/toolchain/linux/iphone and run the installer by hand without CI
#     set.
#
#  3. Re-running. install-theos is idempotent, but its dependency step is not
#     free: it opens with `sudo apt update` / `sudo dnf group install`, which
#     would ask for a password on every single apply to install nothing. Once
#     Theos is fully present, updating it needs no privileges at all -- so the
#     installer is only reached when something is actually missing, and the
#     steady state is a bare update-theos.
#
# Nothing here is fatal. A network failure or a half-finished toolchain is
# worth a warning; it is not worth aborting the apply and taking down every
# script ordered after this one.

# Must match .commonprofile. The preamble does not source it -- each script is
# its own process and starts from a non-login environment.
export THEOS="$HOME/theos"

THEOS_INSTALLER="https://raw.githubusercontent.com/theos/theos/master/bin/install-theos"

theos_skip() {
	echo "warning: skipping Theos: $1" >&2
	return 0
}

theos_supported() {
	if [ "$CONTAINERIZED" -eq 1 ]; then
		# Same reasoning as the VSCode rule in .chezmoiignore: the published
		# images run a full apply at build time, and a toolchain plus the
		# patched SDKs is a few gigabytes of image for a thing nobody is going
		# to build tweaks in from a container.
		theos_skip "containerized host"
		return 1
	fi

	if [ "$IS_ATOMIC" -eq 1 ]; then
		# install-theos's redhat branch is `sudo dnf group install c-development`
		# plus `sudo dnf install ...`, and /usr belongs to the bootc image. The
		# transaction cannot succeed, so do not start it.
		theos_skip "atomic host, where install-theos's dnf transaction cannot write to /usr"
		return 1
	fi

	if [ "$(uname)" = "Darwin" ]; then
		# install-theos exits 3 unless xcode-select points at an Xcode.app --
		# the Command Line Tools that the preamble installs are explicitly not
		# enough, since Theos needs the iOS/tvOS platform toolchains that only
		# the full Xcode ships. Nothing here can install Xcode (it is not on
		# brew, and `mas` cannot drive it -- see 060-mac-app-store), so say so
		# and move on.
		if ! [ -d /Applications/Xcode.app/Contents/Developer ]; then
			theos_skip "Xcode.app is not installed; the Command Line Tools alone cannot build for iOS"
			return 1
		fi
		# The installer fixes a CLT-selected developer directory itself, with
		# sudo. Only worth reaching if we can actually give it one.
		if [ "$(xcode-select -p 2>/dev/null || true)" = "/Library/Developer/CommandLineTools" ] && ! can_sudo; then
			theos_skip "developer directory is the Command Line Tools and sudo isn't available to switch it"
			return 1
		fi
	elif ! can_sudo && ! theos_complete; then
		# Only the run that reaches install-theos is privileged, and only for
		# the distro packages it installs. A complete install updates fine
		# without sudo -- and note this is theos_complete, not a bare `-d
		# $THEOS`: a checkout whose toolchain never finished still has to go
		# back through the installer, so it is not the unprivileged case.
		theos_skip "install-theos needs sudo for its build dependencies"
		return 1
	fi

	return 0
}

# "Installed" means all three pieces, not just the checkout: a clone whose
# toolchain download failed halfway leaves a perfectly populated $THEOS that
# cannot compile anything, and update-theos will not notice or repair it.
theos_complete() {
	[ -d "$THEOS" ] && [ -n "$(ls -A "$THEOS" 2>/dev/null)" ] || return 1
	[ -n "$(ls -A "$THEOS/sdks" 2>/dev/null | grep sdk || true)" ] || return 1
	# macOS uses Xcode's own toolchain; only Linux downloads one.
	if [ "$(uname)" != "Darwin" ]; then
		[ -x "$THEOS/toolchain/linux/iphone/bin/clang" ] || return 1
	fi
	return 0
}

if theos_supported; then
	if theos_complete; then
		echo "note: updating Theos in $THEOS" >&2
		"$THEOS/bin/update-theos" || echo "warning: update-theos failed; leaving the existing install alone" >&2
	else
		echo "note: installing Theos into $THEOS" >&2
		# CI=1: see (2) above. The installer refuses to run under sudo itself
		# and acquires it per-command, which is why this is a plain bash.
		CI=1 bash -c "$(curl -fsSL "$THEOS_INSTALLER")" \
			|| echo "warning: install-theos failed; see the log above" >&2
	fi
fi
