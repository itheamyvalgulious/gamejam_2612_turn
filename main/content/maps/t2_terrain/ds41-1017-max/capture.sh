#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
SHOTS="${SHOTS:-hero_dusk,snow_edge,forest,gorge,river,panorama,detail_rock,rock_1m,detail_snow,detail_tree,detail_leaf,detail_water,detail_waterfall,waterfall_20m}"
RES="${RES:-1024}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
exec godot --path . -- --shot="$SHOTS" --res="$RES"
