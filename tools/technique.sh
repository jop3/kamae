#!/usr/bin/env bash
# Builds a technique script and renders it: poses + sequence, Front/Side stills per phase, an MP4
# and a contact sheet of every phase, all under techniques/build/<slug>/.
#   GODOT=/path/to/godot tools/technique.sh techniques/katatedori_tenkan.json [--no-video]
# SKIP_BUILD=1 re-renders the last build; REF_VIDEO=clip.mp4 adds a video-vs-render comparison
# for phases that carry a "ref" time. MOTION=0 skips the frame-by-frame check of the blends.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
script="$1"; shift || true
video=1; [ "${1:-}" = "--no-video" ] && video=0
RUN="$GODOT"; if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then RUN="xvfb-run -a $GODOT"; fi
mkdir -p techniques/build && touch techniques/build/.gdignore
timeout 120 "$GODOT" --headless --import >/dev/null 2>&1 || true
if [ "${SKIP_BUILD:-0}" = 1 ]; then   # re-render (or compare) what was built last time
  slug=$(python3 -c "import json,re,sys; print(re.sub(r'[^a-z0-9]+','_',json.load(open(sys.argv[1]))['name'].lower()).strip('_'))" "$script")
  out="$PWD/techniques/build/$slug/sequences/$slug.json"
else
  out=$(timeout 600 "$GODOT" --headless -s tools/build_technique.gd -- "$PWD/$script" 2>&1 | tee /dev/stderr | sed -n 's/^sequence: //p' | tail -1)
fi
[ -n "$out" ] || { echo "build failed" >&2; exit 1; }
dir=$(dirname "$(dirname "$out")"); slug=$(basename "$out" .json)
rm -rf "$dir/stills"; mkdir -p "$dir/stills"
timeout 600 $RUN --path . --resolution 1920x1080 -- --render-stills "$out" --poses-dir "$dir/poses" --stills-dir "$dir/stills" 2>&1 | grep -E "SCRIPT ERROR|still saved" || true
if command -v ffmpeg >/dev/null; then
  # One row per phase in the sequence's order, Front beside Side, small enough to read at once.
  order=$(python3 -c "import json,sys; print(' '.join(s['pose'] for s in json.load(open(sys.argv[1]))['steps']))" "$out")
  args=(); n=0
  for p in $order; do
    phase=${p#${slug}_}; [ "$phase" = "$p" ] && phase=$p
    f="$dir/stills/${slug}_${phase}"
    [ -f "${f}_front.png" ] || f=$(ls "$dir"/stills/*"${phase}"_front.png | head -1 | sed 's/_front.png$//')
    second="${f}_side.png"; [ -f "${f}_view.png" ] && second="${f}_view.png"   # a script's chosen view
    args+=(-i "${f}_front.png" -i "$second"); n=$((n+1))
  done
  filter=""; for i in $(seq 0 $((n-1))); do
    filter+="[$((2*i)):v]scale=640:-1[a$i];[$((2*i+1)):v]scale=640:-1[b$i];[a$i][b$i]hstack[r$i];"; done
  for i in $(seq 0 $((n-1))); do filter+="[r$i]"; done
  ffmpeg -v error -y "${args[@]}" -filter_complex "${filter}vstack=inputs=$n" "$dir/contact_sheet.png"
  echo "contact sheet: $dir/contact_sheet.png"
fi
# The frames between the poses, checked like the poses (tests/check_motion.gd): a limb that
# sweeps through a body on the way from one phase to the next shows here and nowhere else.
if [ "${MOTION:-1}" = 1 ]; then
  MOTION_REPORT=1 MOTION_SEQS_DIR="$(dirname "$out")" MOTION_POSES_DIR="$dir/poses" \
    timeout 900 "$GODOT" --headless -s tests/check_motion.gd 2>&1 | sed -n '/^MOTION/,/^RESULT/p' | grep -v "^RESULT" | tee "$dir/motion.txt"
fi
if [ "$video" = 1 ]; then
  rm -rf "$dir/frames"; mkdir -p "$dir/frames"
  timeout 900 $RUN --path . --write-movie "$dir/frames/f.png" --fixed-fps 30 -- --render-sequence "$out" --poses-dir "$dir/poses" 2>&1 | grep -E "SCRIPT ERROR|sequence rendered" || true
  if command -v ffmpeg >/dev/null; then
    ffmpeg -v error -y -framerate 30 -i "$dir/frames/f%08d.png" -c:v libx264 -pix_fmt yuv420p -crf 20 "$dir/$slug.mp4"
    rm -rf "$dir/frames"
    echo "video: $dir/$slug.mp4"
  fi
fi
# With REF_VIDEO set and a "ref" time (seconds) on the phases, put the video's frame beside the
# render for each phase: the check that a technique built from a video matches it.
if [ -n "${REF_VIDEO:-}" ] && command -v ffmpeg >/dev/null; then
  mkdir -p "$dir/compare"; args=(); n=0
  while read -r name t; do
    p=$(python3 -c "import sys,re; print(re.sub(r'[^a-z0-9]+','_',sys.argv[1].lower()).strip('_'))" "$name")
    ffmpeg -nostdin -v error -y -ss "$t" -i "$REF_VIDEO" -frames:v 1 -vf "scale=640:-2" "$dir/compare/ref_$p.png"
    still="$dir/stills/${slug}_${p}_side.png"; [ -f "$dir/stills/${slug}_${p}_view.png" ] && still="$dir/stills/${slug}_${p}_view.png"
    args+=(-i "$dir/compare/ref_$p.png" -i "$still"); n=$((n+1))
  done < <(python3 -c "
import json,sys
for ph in json.load(open(sys.argv[1])).get('phases',[]):
    if 'ref' in ph and ph.get('save',True): print(ph['name'], ph['ref'])" "$script")
  if [ "$n" -gt 0 ]; then
    filter=""; for i in $(seq 0 $((n-1))); do
      filter+="[$((2*i)):v]scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:-1:-1[a$i];[$((2*i+1)):v]scale=640:360[b$i];[a$i][b$i]hstack[r$i];"; done
    for i in $(seq 0 $((n-1))); do filter+="[r$i]"; done
    ffmpeg -v error -y "${args[@]}" -filter_complex "${filter}vstack=inputs=$n" "$dir/compare_with_video.png"
    echo "comparison: $dir/compare_with_video.png"
  fi
fi
