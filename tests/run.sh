#!/usr/bin/env bash
# Runs headless tests, then renders a screenshot under Xvfb if available.
#   GODOT=/path/to/godot tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p tests/out
"$GODOT" --headless --import >/dev/null 2>&1
status=0
for t in tests/test_*.gd; do
  echo "== $t"
  "$GODOT" --headless -s "$t" 2>&1 | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR|ERROR" || true
  "$GODOT" --headless -s "$t" >/dev/null 2>&1 || status=1
done
RUN="$GODOT"; if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then RUN="xvfb-run -a $GODOT"; fi
echo "== screenshot"
$RUN --resolution 1600x900 -- --screenshot "$PWD/tests/out/m0.png" 2>&1 | grep -E "screenshot|SCRIPT ERROR" || true
[ -s tests/out/m0.png ] && echo "OK tests/out/m0.png" || { echo "FAIL no screenshot"; status=1; }
exit $status
