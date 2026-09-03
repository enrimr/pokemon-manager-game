#!/bin/bash
# Export release builds for all four platforms into dist/.
# Requires the Godot 4.6 export templates (see docs/TESTING.md §5).
set -uo pipefail

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# refuse to export a project that doesn't boot cleanly (other agents mid-edit,
# broken scripts, etc.) — a build with parse errors is worse than no build.
echo "== preflight: headless boot check =="
BOOT_LOG=$(caffeinate -i timeout 120 "$GODOT" --headless --path "$ROOT" --quit-after 60 2>&1)
if echo "$BOOT_LOG" | grep -q "SCRIPT ERROR"; then
    echo "$BOOT_LOG" | grep "SCRIPT ERROR" | head -5
    echo "EXPORT ABORTED: project has script errors"
    exit 1
fi

echo "v$(date +%Y.%m.%d) · $(git rev-parse --short HEAD)" > version.txt

mkdir -p dist/macos dist/windows dist/linux dist/web
FAIL=0
for PRESET in "macOS" "Windows Desktop" "Linux/X11" "Web"; do
    echo "== exporting: $PRESET =="
    if ! caffeinate -i timeout 600 "$GODOT" --headless --path "$ROOT" \
            --export-release "$PRESET" 2>&1 | grep -iE "^ERROR|Failed to export" ; then
        : # no error lines is good
    fi
done

echo "== artifacts =="
STATUS=0
check() { # path, min bytes
    local size
    size=$(stat -f%z "$1" 2>/dev/null || echo 0)
    if [ "$size" -ge "$2" ]; then
        echo "  ok: $1 ($size bytes)"
    else
        echo "  MISSING/TOO SMALL: $1 ($size bytes, wanted >= $2)"
        STATUS=1
    fi
}
check dist/macos/TrainerManager-macos.zip 30000000
check dist/windows/TrainerManager.exe     60000000
check dist/linux/TrainerManager.x86_64    60000000
check dist/web/index.html                 5000
check dist/web/index.wasm                 20000000
check dist/web/index.pck                  1000000

if [ "$STATUS" -eq 0 ]; then
    echo "EXPORT ALL OK"
else
    echo "EXPORT ALL FAILED"
fi
exit $STATUS
