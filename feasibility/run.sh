#!/usr/bin/env bash
# Feasibility harness for the Kamae posing tool. Requires a Godot 4.6.x binary.
#   GODOT=/path/to/Godot_v4.6-stable_linux.x86_64 ./feasibility/run.sh
# Movie/still tests need a display; on a headless box install xvfb and it is used automatically.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --version

echo "== grip-follow tracking error (mm) per sync mode and scene-tree order =="
"$GODOT" --headless --path iktest --import >/dev/null 2>&1 || true
for order in uke_first tori_first; do
  for mode in process signal signal_direct manual manual_direct; do
    "$GODOT" --headless --path iktest -- "$mode" "$order" 2>&1 | grep RESULT
  done
done

echo "== TwoBoneIK3D solve + pose transience (pose read in _process vs skeleton_updated) =="
"$GODOT" --headless --path iktest dbg.tscn -- two 2>&1 | grep -E "^(process|  )" | head -6

echo "== custom SkeletonModifier3D orients end bone after IK =="
"$GODOT" --headless --path iktest handrot.tscn 2>&1 | grep -E "^f" | head -2

RUN="$GODOT"; if ! [ -n "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then RUN="xvfb-run -a $GODOT"; fi
echo "== still export with transparent background + Movie Maker formats =="
mkdir -p movietest/out
$RUN --headless --path movietest --import >/dev/null 2>&1 || true
$RUN --path movietest 2>&1 | grep -E "^still"
$RUN --path movietest --write-movie out/seq.png --fixed-fps 30 2>&1 | grep -E "frames"
$RUN --path movietest --write-movie out/clip.avi --fixed-fps 30 2>&1 | grep -E "frames"
$RUN --path movietest --write-movie out/clip.ogv --fixed-fps 30 2>&1 | grep -E "frames"
ls -la movietest/out | head
