# ~/repositories/dotfiles: a symlink to this chezmoi source, so the clone sits
# with the other repositories. For 00-{linux,macos}/002-repositories-dotfiles;
# 00-nt/070-repositories-dotfiles is the Windows one.
#
# ~/repositories itself is symlink_repositories on Windows and in WSL, and a
# plain directory everywhere else that only hookscripts create, so nothing
# under it can be a chezmoi entry: this script makes the link. In WSL the
# directory is on the wslpersist volume, which every regulad-* instance
# shares, so the link is absolute: each instance resolves it to its own clone.
REPOS_DIR="$HOME/repositories"
DOTFILES_LINK="$REPOS_DIR/dotfiles"
DOTFILES_SOURCE={{ .chezmoi.workingTree | quote }}

mkdir -p "$REPOS_DIR"
if [ -L "$DOTFILES_LINK" ]; then
	if [ "$(readlink "$DOTFILES_LINK")" = "$DOTFILES_SOURCE" ]; then
		echo "debug: $DOTFILES_LINK already points at $DOTFILES_SOURCE" >&2
		exit 0
	fi
	echo "notice: $DOTFILES_LINK pointed at $(readlink "$DOTFILES_LINK"); repointing it at $DOTFILES_SOURCE" >&2
	rm -f "$DOTFILES_LINK"
elif [ -e "$DOTFILES_LINK" ]; then
	if [ "$DOTFILES_LINK" -ef "$DOTFILES_SOURCE" ]; then
		echo "debug: the chezmoi source is $DOTFILES_LINK itself" >&2
	else
		echo "warning: $DOTFILES_LINK exists and is not a symlink; leaving it, so it does not point at $DOTFILES_SOURCE" >&2
	fi
	exit 0
else
	echo "notice: linking $DOTFILES_LINK to $DOTFILES_SOURCE" >&2
fi
ln -s "$DOTFILES_SOURCE" "$DOTFILES_LINK"
