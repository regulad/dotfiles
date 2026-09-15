# Clones the projectM "Cream of the Crop" preset pack (~9,800 curated Milkdrop
# presets, projectM's default pack since 2022), then flattens it: VLC bundles
# libprojectM 2.0.1 (contrib/src/projectM/rules.mak in vlc-3.0), whose
# PresetLoader::rescan() is a single readdir() pass -- recursive scanning only
# landed upstream in projectM-visualizer/projectm#385, in a major VLC never
# adopted -- and the pack nests every preset in category subdirectories.
# presets-flat is what
# dot_config/vlc/vlcrc points projectm-preset-path at -- hardlinks, so it
# costs no space, and the pack has no name collisions or texture files to
# worry about (verified: 9,795 uniquely-named .milk files, nothing else).
#
# run_once_ + the exists guards: the pack is static content, so there is
# nothing to refresh on every apply, and a re-run (this template's hash
# changing) redoes only the steps whose output is missing.
PRESET_DIR="$HOME/.local/share/projectM/presets"
FLAT_DIR="$HOME/.local/share/projectM/presets-flat"

if [ ! -d "$PRESET_DIR/.git" ]; then
	echo "note: cloning projectM presets into $PRESET_DIR" >&2
	mkdir -p "$(dirname "$PRESET_DIR")"
	git clone --depth 1 https://github.com/projectM-visualizer/presets-cream-of-the-crop "$PRESET_DIR"
else
	echo "note: projectM presets already present, skipping clone" >&2
fi

if [ ! -d "$FLAT_DIR" ]; then
	echo "note: flattening presets into $FLAT_DIR" >&2
	# Build in a temp dir and rename into place, so a half-built flat dir from
	# an interrupted run can never satisfy the exists-guard above.
	FLAT_TMP="$FLAT_DIR.tmp"
	rm -rf "$FLAT_TMP"
	mkdir -p "$FLAT_TMP"
	# ln into a directory, batched through sh -c so BSD ln (macOS) works too;
	# the _ placeholder is $0 inside the inner shell.
	FLAT_TMP="$FLAT_TMP" find "$PRESET_DIR" -name '*.milk' \
		-exec sh -c 'ln -f "$@" "$FLAT_TMP"' _ {} +
	mv "$FLAT_TMP" "$FLAT_DIR"
else
	echo "note: flattened presets already present, skipping" >&2
fi
