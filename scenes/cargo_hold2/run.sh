#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
engine="${GODOT_BIN:-godot}"
# Always repair incomplete imports, even when the script class cache exists.
"$engine" --headless --editor --path . --import --quit
exec "$engine" --path . "$@"
