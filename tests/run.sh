#!/usr/bin/env bash
# Runs headless tests, then renders a screenshot under Xvfb if available.
#   GODOT=/path/to/godot tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# A script that fails to compile leaves Godot spinning in its main loop, so every run is bounded.
TIMEOUT="${TIMEOUT:-180}"
run() { timeout "$TIMEOUT" "$@"; }
mkdir -p tests/out
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
exit $status
