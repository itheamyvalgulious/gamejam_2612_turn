#!/usr/bin/env bash
# 启动本工程（在任意目录执行均可；首次运行自动生成 .godot 导入缓存）
set -e
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  # class_name 索引在首次导入时才生成；缓存缺失会导致脚本解析失败
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
exec godot --path . "$@"
