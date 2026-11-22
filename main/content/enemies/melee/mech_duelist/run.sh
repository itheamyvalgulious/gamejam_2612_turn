#!/usr/bin/env bash
# 启动 demo（可传 godot 参数，例如 -- --quit-after 600）
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
exec godot --path . "$@"
