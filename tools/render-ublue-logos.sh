#!/usr/bin/env sh
# Regenerate dot_config/fastfetch/logos/ from ublue's mascot PNGs.
#
# Run this by hand on a Bluefin host and commit the result; it is not a
# .chezmoiscript, because /usr/share/ublue-os/bluefin-logos only exists on
# Bluefin and the output is checked in so every other host gets nothing.
#
# Why pre-render at all, rather than let the MOTD convert PNGs on the fly:
# fastfetch's own image path is gated behind FF_HAVE_IMAGEMAGICK{6,7} in
# src/logo/image/image.c and dlopens MagickCore -- chafa decodes nothing itself,
# it only colours pixels ImageMagick already produced. That proved unreliable
# here: with fastfetch, chafa and imagemagick all installed and `magick identify`
# reading the files fine, fastfetch still failed with "Failed to load / convert
# the image source". A text file needs none of that on every interactive shell.
#
# == Sizing
#
# HEIGHT is the whole design constraint. This repo's fastfetch config prints 12
# module lines, and fastfetch sets the block height to whichever of the logo and
# the module list is taller -- so any logo up to 12 rows is free, and one row
# taller costs a row of terminal on every single shell. 11 rows plus the one-line
# gap fastfetch leaves lands exactly on 12.
#
# Width is deliberately not pinned. --size takes a bounding box and chafa
# preserves aspect within it, so a generous width lets HEIGHT bind for every
# mascot regardless of its shape (they range from 0.75 to 1.13 w/h).
#
# The previous renders were 16x9 and used only U+2580/2584 half blocks, which is
# where the "one solid block per cell" look came from. At 11 rows with the fuller
# symbol set below, chicken goes from 128 cells to 275 -- 2.1x the detail, and
# still 12 lines of splash.
#
# == Symbols
#
# block+border+space is what makes cells partially filled rather than solid: it
# admits the eighth-blocks (U+2581-2587, U+2589-258F), quadrants (U+2596-259F)
# and box-drawing glyphs that ublue's own symbols/ renders use. Restricting to
# half blocks throws that away and quantises every cell to two stacked pixels.
#
# Deliberately excluded: sextant/octant (U+1FB00, U+1CD00) would roughly double
# the effective resolution again, but they are recent additions that many fonts
# still lack, and a missing glyph renders as tofu -- not worth it for a MOTD that
# has to look right on a fresh install. braille is excluded for the same reason
# plus it cannot carry two colours per cell.
set -eu

SRC_DIR="${SRC_DIR:-/usr/share/ublue-os/bluefin-logos}"
OUT_DIR="${OUT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/dot_config/fastfetch/logos}"
HEIGHT="${HEIGHT:-11}"
SYMBOLS="${SYMBOLS:-block+border+space}"

command -v chafa >/dev/null 2>&1 || { echo "error: chafa is not installed" >&2; exit 1; }
[ -d "$SRC_DIR" ] || { echo "error: $SRC_DIR not found (not a Bluefin host?)" >&2; exit 1; }

mkdir -p "$OUT_DIR"

for png in "$SRC_DIR"/*.png; do
    [ -e "$png" ] || { echo "error: no PNGs in $SRC_DIR" >&2; exit 1; }
    name="$(basename "$png" .png)"

    # --polite on suppresses the cursor hide/show (CSI ?25l / ?25h) that chafa
    # otherwise wraps its output in. Those are invisible when chafa writes to a
    # terminal, but they get baked into the file and then replayed by fastfetch
    # in the middle of a prompt.
    #
    # -c full because the mascots are truecolor photographs of a sort, not
    # palette art; anything less bands them badly at this size.
    #
    # Transparency is left to chafa's default alpha threshold: the mascots are
    # alpha=Blend, and cells outside the silhouette come out as an uncoloured
    # space, so the logo sits on the terminal background instead of in a box.
    chafa \
        --format symbols \
        --colors full \
        --polite on \
        --symbols "$SYMBOLS" \
        --size "$((HEIGHT * 4))x${HEIGHT}" \
        "$png" > "$OUT_DIR/$name"

    # fastfetch's "file" logo type does colour-code replacement, so a literal $
    # in the art would be eaten as a placeholder. Nothing chafa emits contains
    # one, but assert it rather than find out on a future mascot.
    if grep -q '\$' "$OUT_DIR/$name"; then
        echo "error: $name contains a literal \$; use logo type file-raw" >&2
        exit 1
    fi

    printf '%-10s %sx%s\n' "$name" \
        "$(sed 's/\x1b\[[0-9;]*m//g' "$OUT_DIR/$name" | awk '{ print length }' | sort -rn | head -1)" \
        "$(wc -l < "$OUT_DIR/$name")"
done
