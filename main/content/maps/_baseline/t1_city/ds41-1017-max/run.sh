#!/usr/bin/env bash
# Launch the procedural city.  Pass extra args after -- to the game, e.g.
#   ./run.sh -- --preset=day --bench=1
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  # class_name 索引在首次导入时才生成；缓存缺失会导致脚本解析失败
  godot --headless --path . --import >/dev/null 2>&1 || true
fi

exec godot --path . "$@"
