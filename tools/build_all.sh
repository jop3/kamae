#!/usr/bin/env bash
# Builds and renders every technique script, then the gallery page that shows them all.
#   GODOT=/path/to/godot tools/build_all.sh        (about 3-5 minutes per technique)
set -uo pipefail
cd "$(dirname "$0")/.."
for s in techniques/*.json; do
  echo "== $s"
  tools/technique.sh "$s" 2>&1 | grep -E "^pose|^MOTION|^FLOOR|video:|SCRIPT ERROR|ERRORS" || true
done
python3 tools/gallery.py
