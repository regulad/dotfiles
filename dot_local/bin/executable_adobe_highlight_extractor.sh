#!/usr/bin/env bash
# SPDX-License-Identifier: Unlicense
#
# This is free and unencumbered software released into the public domain.
#
# This script was generated entirely by a large language model (LLM) and,
# as a work lacking human authorship, is not eligible for copyright protection
# and is therefore in the public domain. The Unlicense is applied as an
# explicit dedication where copyright might otherwise be claimed.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or distribute
# this software, either in source code form or as a compiled binary, for any
# purpose, commercial or non-commercial, and by any means.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
#
# ---------------------------------------------------------------------------
# extract_highlights.sh
#
# Finds all *A.pdf files in the current directory, extracts every highlighted
# section added by Adobe Acrobat (or any conforming PDF writer), and writes
# a CSV file with three columns:
#
#   prefix   – the part of the filename before the trailing "A" (stem sans ext)
#   page     – 1-based page number of the highlight
#   text     – text content of the highlighted region
#
# Output file: highlights.csv  (written to the current directory)
#
# Requirements: python3 (3.8+) on PATH; internet access for first run
#               (pip installs pypdf and pdfplumber into a temporary venv).
#
# Usage:
#   bash extract_highlights.sh            # processes *A.pdf in CWD
#   bash extract_highlights.sh foo/BarA.pdf baz/QuxA.pdf   # explicit files
# ---------------------------------------------------------------------------

set -euo pipefail

OUTPUT="highlights.csv"

# --------------------------------------------------------------------------
# 1. Create a throwaway virtual environment in a temp directory so we never
#    touch the system Python installation.  Works on macOS and GNU/Linux.
# --------------------------------------------------------------------------
VENV_DIR="$(mktemp -d)"
trap 'rm -rf "$VENV_DIR"' EXIT

echo "[setup] Creating temporary venv in $VENV_DIR ..." >&2
python3 -m venv "$VENV_DIR"

VENV_PY="$VENV_DIR/bin/python3"
VENV_PIP="$VENV_DIR/bin/pip"

echo "[setup] Installing pypdf and pdfplumber ..." >&2
"$VENV_PIP" install --quiet --disable-pip-version-check pypdf pdfplumber

# --------------------------------------------------------------------------
# 2. Run the extraction logic with the venv interpreter.
#    Pass the output path as $1; any extra args are treated as explicit files.
# --------------------------------------------------------------------------
"$VENV_PY" - "$OUTPUT" "$@" << 'PYEOF'
"""
Extract highlighted text from *A.pdf files, handling Adobe Acrobat's
QuadPoints format correctly.

Adobe Acrobat specifics handled here:
  * QuadPoints vertex order: TL, TR, BR, BL  (spec says TL, TR, BL, BR --
    Acrobat swaps the last two pairs).  We use min/max so order is irrelevant.
  * Multi-line highlights: a single annotation may carry Nx8 floats in
    QuadPoints, one group of 8 per highlighted line.  Each quad is cropped
    and extracted independently, then the results are joined.
  * /Rect unreliability: Acrobat sometimes writes a /Rect that is the union
    of all quads, but the spec says it *may* be invalid when QuadPoints are
    present (pdf.js bug #6811).  We always prefer QuadPoints; /Rect is only
    used as a last resort when QuadPoints is absent.
  * Non-zero MediaBox origin: some PDFs set MediaBox to e.g. [18 18 594 774].
    Coordinate conversion accounts for llx/lly offsets so pdfplumber crops
    are correct regardless of origin.
"""

import sys
import csv
import glob
import os
import re

import pypdf
import pdfplumber

output_file = sys.argv[1]

# Collect *A.pdf targets -- either passed explicitly or globbed from CWD.
if len(sys.argv) > 2:
    pdf_files = sys.argv[2:]
else:
    pdf_files = sorted(glob.glob("*A.pdf"))

if not pdf_files:
    print("No *A.pdf files found.", file=sys.stderr)
    sys.exit(0)


def quads_from_annotation(annot):
    """
    Return a list of (x0, y0, x1, y1) bounding boxes in raw PDF coordinates
    (bottom-left origin) for a single highlight annotation.

    QuadPoints groups: each group of 8 floats encodes one quadrilateral.
    Regardless of the per-group vertex ordering (Acrobat vs. spec), taking
    min/max of the 4 x-values and 4 y-values gives the correct bbox.

    Falls back to /Rect only if QuadPoints is absent.
    """
    quad_pts = annot.get("/QuadPoints")
    if quad_pts:
        pts = [float(v) for v in quad_pts]
        boxes = []
        for i in range(0, len(pts), 8):
            group = pts[i : i + 8]
            if len(group) < 8:
                continue
            xs = group[0::2]
            ys = group[1::2]
            boxes.append((min(xs), min(ys), max(xs), max(ys)))
        if boxes:
            return boxes

    # Fallback: /Rect
    rect = annot.get("/Rect")
    if rect:
        x0, y0, x1, y1 = [float(v) for v in rect]
        return [(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))]

    return []


def pdf_bbox_to_plumber(x0, y0_pdf, x1, y1_pdf, mediabox):
    """
    Convert a bounding box from PDF coordinate space (bottom-left origin,
    y increases upward) to pdfplumber crop coordinates (top-left origin,
    y increases downward).

    mediabox is the pypdf RectangleObject for the page: [llx, lly, urx, ury].
    """
    llx = float(mediabox[0])
    lly = float(mediabox[1])
    ury = float(mediabox[3])

    # pdfplumber measures from the top-left corner of the MediaBox.
    plumb_x0     = x0    - llx
    plumb_x1     = x1    - llx
    plumb_top    = ury   - y1_pdf   # y1_pdf is the higher PDF y -> smaller top
    plumb_bottom = ury   - y0_pdf   # y0_pdf is the lower PDF y  -> larger bottom

    return plumb_x0, plumb_top, plumb_x1, plumb_bottom


def extract_highlights(pdf_path):
    """
    Yield (page_num, text) for every Highlight annotation in the PDF.
    page_num is 1-based.  Multi-line highlights (multiple quads) are
    extracted line-by-line and joined with a space.
    """
    TOLERANCE = 1.5   # pts -- avoids clipping glyphs on annotation edges

    reader = pypdf.PdfReader(pdf_path)
    with pdfplumber.open(pdf_path) as pdf:
        for page_idx, (pypdf_page, plumb_page) in enumerate(
            zip(reader.pages, pdf.pages)
        ):
            page_num = page_idx + 1
            annots_obj = pypdf_page.get("/Annots")
            if not annots_obj:
                continue

            # Resolve indirect array reference if needed.
            if hasattr(annots_obj, "get_object"):
                annots_obj = annots_obj.get_object()

            mediabox = pypdf_page.mediabox

            for annot_ref in annots_obj:
                annot = (
                    annot_ref.get_object()
                    if hasattr(annot_ref, "get_object")
                    else annot_ref
                )
                if annot.get("/Subtype") != "/Highlight":
                    continue

                quad_boxes = quads_from_annotation(annot)
                if not quad_boxes:
                    continue

                line_texts = []
                for (x0, y0_pdf, x1, y1_pdf) in quad_boxes:
                    plumb_x0, plumb_top, plumb_x1, plumb_bottom = \
                        pdf_bbox_to_plumber(x0, y0_pdf, x1, y1_pdf, mediabox)

                    crop_box = (
                        plumb_x0 - TOLERANCE,
                        plumb_top - TOLERANCE,
                        plumb_x1 + TOLERANCE,
                        plumb_bottom + TOLERANCE,
                    )

                    try:
                        cropped = plumb_page.crop(crop_box)
                        text = (cropped.extract_text() or "").strip()
                    except Exception:
                        text = ""

                    if text:
                        line_texts.append(text)

                if line_texts:
                    yield page_num, " ".join(line_texts)


def prefix_from_filename(path):
    """Return the filename stem with a trailing 'A' removed."""
    stem = os.path.splitext(os.path.basename(path))[0]   # e.g. "ReportA"
    return stem[:-1] if stem.endswith("A") else stem


rows_written = 0
with open(output_file, "w", newline="", encoding="utf-8") as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow(["prefix", "page", "text"])

    for pdf_path in pdf_files:
        prefix = prefix_from_filename(pdf_path)
        print(f"[extract] {pdf_path}  ->  prefix={prefix!r}", file=sys.stderr)
        try:
            for page_num, text in extract_highlights(pdf_path):
                # Collapse runs of whitespace / newlines for clean CSV cells.
                clean = re.sub(r"\s+", " ", text)
                writer.writerow([prefix, page_num, clean])
                rows_written += 1
        except Exception as exc:
            print(f"  ERROR: {exc}", file=sys.stderr)

print(
    f"[done] {rows_written} highlight(s) written to {output_file}",
    file=sys.stderr,
)
PYEOF
