#!/bin/bash
# Smoke test for Trainer Manager.
#  1. Headless boot of the full game (shell + autoloads), quit after 60 frames.
#  2. Headless 50-day season fast-forward + battle engine checks (sim_check).
# Exits nonzero on any SCRIPT ERROR / ERROR / check failure.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

echo "== smoke 1/2: headless boot =="
BOOT_LOG=$("$GODOT" --headless --path "$ROOT" --quit-after 60 2>&1)
BOOT_RC=$?
echo "$BOOT_LOG"
if [ $BOOT_RC -ne 0 ]; then
  echo "SMOKE FAIL: boot exited with code $BOOT_RC"
  FAIL=1
fi
if echo "$BOOT_LOG" | grep -E "SCRIPT ERROR|^ERROR|WARNING: .*res://" >/dev/null; then
  echo "SMOKE FAIL: errors during boot"
  FAIL=1
fi

echo ""
echo "== smoke 2/2: 50-day season sim (sim_check) =="
SIM_LOG=$("$GODOT" --headless --path "$ROOT" res://tools/sim_check.tscn 2>&1)
SIM_RC=$?
echo "$SIM_LOG"
if [ $SIM_RC -ne 0 ]; then
  echo "SMOKE FAIL: sim_check exited with code $SIM_RC"
  FAIL=1
fi
if echo "$SIM_LOG" | grep -E "SCRIPT ERROR|FAIL:" >/dev/null; then
  echo "SMOKE FAIL: errors during sim_check"
  FAIL=1
fi
if ! echo "$SIM_LOG" | grep -q "SIM CHECK OK"; then
  echo "SMOKE FAIL: sim_check did not report OK"
  FAIL=1
fi

echo ""
if [ $FAIL -eq 0 ]; then
  echo "SMOKE OK"
else
  echo "SMOKE FAILED"
fi
exit $FAIL
