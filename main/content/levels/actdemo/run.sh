#!/usr/bin/env bash
# 启动 demo（可传 godot 参数，例如 -- --quit-after 600）
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  # class_name 索引在首次导入时才生成；缓存缺失会导致脚本/字体解析失败
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
exec godot --path . "$@"
