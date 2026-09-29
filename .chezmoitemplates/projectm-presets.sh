# Clones the projectM "Cream of the Crop" preset pack (~9,800 curated Milkdrop
# presets, projectM's default pack since 2022), then flattens it: VLC bundles
# libprojectM 2.0.1 (contrib/src/projectM/rules.mak in vlc-3.0), whose
# PresetLoader::rescan() is a single readdir() pass -- recursive scanning only
# landed upstream in projectM-visualizer/projectm#385, in a major VLC never
# adopted -- and the pack nests every preset in category subdirectories.
# presets-flat is what
# dot_config/vlc/vlcrc points projectm-preset-path at -- copy-on-write
# clones where the filesystem has them (APFS on macOS, btrfs/xfs/bcachefs on
# Linux), so it costs no space yet stays independent of the git checkout, and
# a plain copy elsewhere; the pack has no name collisions or texture files to
# worry about (verified: 9,795 uniquely-named .milk files, nothing else).
#
# run_once_ + the exists guards: the pack is static content, so there is
# nothing to refresh on every apply, and a re-run (this template's hash
# changing) redoes only the steps whose output is missing.
PRESET_DIR="$HOME/.local/share/projectM/presets"
FLAT_DIR="$HOME/.local/share/projectM/presets-flat"

if [ ! -d "$PRESET_DIR/.git" ]; then
	echo "debug: cloning projectM presets into $PRESET_DIR" >&2
	mkdir -p "$(dirname "$PRESET_DIR")"
	git clone --depth 1 https://github.com/projectM-visualizer/presets-cream-of-the-crop "$PRESET_DIR"
else
	echo "debug: projectM presets already present, skipping clone" >&2
fi

if [ ! -d "$FLAT_DIR" ]; then
	echo "debug: flattening presets into $FLAT_DIR" >&2
	# Build in a temp dir and rename into place, so a half-built flat dir from
	# an interrupted run can never satisfy the exists-guard above.
	FLAT_TMP="$FLAT_DIR.tmp"
	rm -rf "$FLAT_TMP"
	mkdir -p "$FLAT_TMP"
	# Clone rather than hardlink. macOS: `cp -c` is clonefile(2), a zero-cost
	# APFS clone, and Apple's cp falls back to a regular copy by itself when
	# the volume cannot clone (EXDEV/ENOTSUP); the flag exists from Mojave's
	# file_cmds on, i.e. every release this repo supports. Linux: GNU cp's
	# --reflink=auto is the same idea (btrfs, xfs, bcachefs) with the same
	# built-in fallback. Batched through sh -c with many sources per cp; the
	# _ placeholder is $0 inside the inner shell, and $COPY is left unquoted
	# there on purpose so it splits into the command and its flag.
	case "$(uname -s)" in
		Darwin) COPY="cp -c" ;;
		*) COPY="cp --reflink=auto" ;;
	esac
	COPY="$COPY" FLAT_TMP="$FLAT_TMP" find "$PRESET_DIR" -name '*.milk' \
		-exec sh -c '$COPY "$@" "$FLAT_TMP"' _ {} +
	mv "$FLAT_TMP" "$FLAT_DIR"
else
	echo "debug: flattened presets already present, skipping" >&2
fi
