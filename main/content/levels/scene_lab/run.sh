#!/usr/bin/env bash
# 启动本工程。场景开关：
#   ./run.sh --warehouse     仓库（第 4 关）
#   ./run.sh --panopticon    回廊实验舱（第 5 关）
#   ./run.sh --ward          病房（第 6 关）
#   ./run.sh                 默认进入仓库
# 老写法 ./run.sh -- --ward 仍然有效。
cd "$(dirname "$0")"
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
engine="${GODOT_BIN:-godot}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  # class_name / 字体索引在首次导入时才生成；缓存缺失会导致脚本或字体解析失败
  "$engine" --headless --editor --path . --import --quit >/dev/null 2>&1 || true
fi
# 引擎只把第一个 `--` 之后的参数交给 OS.get_cmdline_user_args()。
# 少了这个分隔符，`./run.sh --ward` 会被当成引擎自己的未知参数吞掉，于是退回默认场景。
args=("$@")
case "${1:-}" in
  --warehouse|--panopticon|--ward) args=(-- "$@") ;;
esac
exec "$engine" --path . "${args[@]}"
