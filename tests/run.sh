#!/usr/bin/env bash
# Runs headless tests, then renders a screenshot under Xvfb if available.
#   GODOT=/path/to/godot tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# A script that fails to compile leaves Godot spinning in its main loop, so every run is bounded.
TIMEOUT="${TIMEOUT:-180}"
run() { timeout "$TIMEOUT" "$@"; }
mkdir -p tests/out exports && touch exports/.gdignore
run "$GODOT" --headless --import >/dev/null 2>&1
status=0
for t in tests/test_*.gd; do
  echo "== $t"
  run "$GODOT" --headless -s "$t" 2>&1 | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR" || true
  run "$GODOT" --headless -s "$t" >/dev/null 2>&1 || status=1
done
RUN="$GODOT"; if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then RUN="xvfb-run -a $GODOT"; fi
echo "== rendered stills"
timeout "$TIMEOUT" $RUN --resolution 1600x900 -- --screenshot "$PWD/tests/out/m1_flat.png" 2>&1 | grep -E "screenshot|SCRIPT ERROR" || true
timeout "$TIMEOUT" $RUN --resolution 1600x900 -- --screenshot-transparent "$PWD/tests/out/m1_transparent.png" 2>&1 | grep -E "screenshot|SCRIPT ERROR" || true
run "$GODOT" --headless -s tests/check_exports.gd 2>&1 | grep -E "^(PASS|FAIL|RESULT)" || true
run "$GODOT" --headless -s tests/check_exports.gd >/dev/null 2>&1 || status=1
echo "== video export (Movie Maker child on the test_m5 sequence)"
rm -rf tests/out/m6 && mkdir -p tests/out/m6/frames
timeout 300 $RUN --path . --write-movie "$PWD/tests/out/m6/frames/f.png" --fixed-fps 30 -- --render-sequence "$PWD/tests/out/poses_m5/katatedori_ikkyo.sequence.json" --poses-dir "$PWD/tests/out/poses_m5" --stills-dir "$PWD/tests/out/m6" 2>&1 | grep -E "sequence rendered|SCRIPT ERROR" || true
echo "== Front+Side stills (child on the test_m5 sequence)"
rm -rf tests/out/m7 && mkdir -p tests/out/m7
timeout 300 $RUN --path . --resolution 1920x1080 -- --render-stills "$PWD/tests/out/poses_m5/katatedori_ikkyo.sequence.json" --poses-dir "$PWD/tests/out/poses_m5" --stills-dir "$PWD/tests/out/m7" 2>&1 | grep -E "SCRIPT ERROR" || true
run "$GODOT" --headless -s tests/check_movie.gd 2>&1 | grep -E "^(PASS|FAIL|RESULT)|ffmpeg" || true
run "$GODOT" --headless -s tests/check_movie.gd >/dev/null 2>&1 || status=1
echo "== acceptance techniques (poses/ and sequences/)"
run "$GODOT" --headless -s tests/check_acceptance.gd 2>&1 | grep -E "^(FAIL|RESULT)" || true
run "$GODOT" --headless -s tests/check_acceptance.gd >/dev/null 2>&1 || status=1
echo "== anatomy: joints, intersections, weapons and skin on every committed pose"
run "$GODOT" --headless -s tests/check_anatomy.gd 2>&1 | grep -E "^(FAIL|RESULT)" || true
run "$GODOT" --headless -s tests/check_anatomy.gd >/dev/null 2>&1 || status=1
if [ "${RENDER_ACCEPTANCE:-1}" = "1" ]; then
  echo "== acceptance exports: Front+Side stills and a video per technique into exports/"
  mkdir -p exports
  for s in sequences/*.json; do
    slug=$(basename "$s" .json)
    timeout 300 $RUN --path . --resolution 1920x1080 -- --render-stills "$PWD/$s" --poses-dir "$PWD/poses" --stills-dir "$PWD/exports" 2>&1 | grep -E "SCRIPT ERROR" || true
    rm -rf "exports/${slug}_frames"; mkdir -p "exports/${slug}_frames"
    timeout 600 $RUN --path . --write-movie "$PWD/exports/${slug}_frames/f.png" --fixed-fps 30 -- --render-sequence "$PWD/$s" --poses-dir "$PWD/poses" --stills-dir "$PWD/exports" 2>&1 | grep -E "SCRIPT ERROR" || true
    if command -v ffmpeg >/dev/null; then
      ffmpeg -y -loglevel error -framerate 30 -i "$PWD/exports/${slug}_frames/f%08d.png" -c:v libx264 -pix_fmt yuv420p "exports/${slug}.mp4" || status=1
    fi
  done
  run "$GODOT" --headless -s tests/check_acceptance_exports.gd 2>&1 | grep -E "^(FAIL|RESULT)" || true
  run "$GODOT" --headless -s tests/check_acceptance_exports.gd >/dev/null 2>&1 || status=1
fi
echo "== golden stills (thumbnails under tests/golden/; UPDATE_GOLDEN=1 to accept new renders)"
run "$GODOT" --headless -s tests/check_golden.gd 2>&1 | grep -E "^(FAIL|RESULT)|golden thumbnails" || true
run "$GODOT" --headless -s tests/check_golden.gd >/dev/null 2>&1 || status=1
exit $status
