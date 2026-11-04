#!/usr/bin/env bash
# Close-ups of a built technique between its keyframes, for looking at what the film is too far
# away to show: an elbow, a face, two bodies in contact.
#   GODOT=/path/to/godot tools/review_frames.sh <slug> [every-seconds | --at t1,t2,...]
# FOCUS=uke1.Head frames that part close up instead of both figures (a face, a hand);
# RADIUS=0.6 with it frames more round that part (metres; 0.18 by default).
# Writes techniques/build/<slug>/review/<slug>_t<time>_{front,side,back,other}.png and a sheet
# per time, review/sheet_t<time>.png (the four views side by side).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
slug="$1"; shift
dir="$PWD/techniques/build/$slug"
args=(--every 0.5)
if [ "${1:-}" = "--at" ]; then args=(--at "$2"); elif [ -n "${1:-}" ]; then args=(--every "$1"); fi
RUN="$GODOT"; if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then RUN="xvfb-run -a $GODOT"; fi
rm -rf "$dir/review"; mkdir -p "$dir/review"
timeout 900 $RUN --path . -- --review-frames "$dir/sequences/$slug.json" \
  --poses-dir "$dir/poses" --out "$dir/review" "${args[@]}" ${FOCUS:+--focus $FOCUS} ${RADIUS:+--radius $RADIUS} 2>&1 | grep -E "SCRIPT ERROR|review frame" || true
if command -v ffmpeg >/dev/null; then
  for f in "$dir"/review/*_front.png; do
    t=$(basename "$f" _front.png); t=${t##*_t}
    b="${f%_front.png}"
    ffmpeg -v error -y -i "${b}_front.png" -i "${b}_side.png" -i "${b}_back.png" -i "${b}_other.png" \
      -filter_complex "[0:v]crop=1080:1080[a];[1:v]crop=1080:1080[b];[2:v]crop=1080:1080[c];[3:v]crop=1080:1080[d];[a][b][c][d]hstack=inputs=4,scale=2400:-1" "$dir/review/sheet_t$t.png"
  done
  echo "review: $dir/review"
fi
