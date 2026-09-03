#!/bin/bash
# Web-only export with a build-version stamp (footer shows it so testers can
# tell at a glance whether they run the latest build).
set -uo pipefail
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "v$(date +%Y.%m.%d) · $(git rev-parse --short HEAD)" > version.txt
caffeinate -i timeout 600 "$GODOT" --headless --path "$ROOT" --export-release "Web" 2>&1 \
    | grep -iE "^ERROR|Failed to export" && exit 1
echo "WEB EXPORT OK ($(cat version.txt))"
