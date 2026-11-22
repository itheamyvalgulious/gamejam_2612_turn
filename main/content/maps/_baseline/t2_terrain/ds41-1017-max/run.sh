#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
exec godot --path . "$@"
