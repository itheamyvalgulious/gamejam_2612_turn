#!/usr/bin/env bash
# TURN Linux launcher: prepare runtime assets, import them, then start the game.
# Mirrors 启动试玩.cmd / main/tools/launch_turn.ps1. Extra args are passed to Godot.
set -u
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"

fail() {
    printf 'TURN 启动失败：%s\n' "$1" >&2
    exit 1
}

# --- locate Godot 4.7.2 ---
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
    for candidate in godot godot4; do
        if command -v "$candidate" >/dev/null 2>&1; then
            GODOT="$(command -v "$candidate")"
            break
        fi
    done
fi
[ -n "$GODOT" ] || fail '找不到 Godot 4.7.2（可设置 GODOT 环境变量指定路径）'
"$GODOT" --version 2>/dev/null | grep -q '^4\.7\.2\.' \
    || fail "Godot 版本不符（需要 4.7.2，当前：$("$GODOT" --version 2>/dev/null || echo 无法运行)）"

# --- locate Python 3 ---
PYTHON="$(command -v python3 || true)"
[ -n "$PYTHON" ] || PYTHON="$(command -v python || true)"
[ -n "$PYTHON" ] || fail '找不到 Python 3'

WORK="$(mktemp -d "${TMPDIR:-/tmp}/TURN-startup-XXXXXX")"
READY="$WORK/ready"
GAME_LOG="$WORK/game.log"

echo '正在准备游戏资源'
"$PYTHON" -X utf8 main/tools/prepare_game.py >"$WORK/prepare.log" 2>"$WORK/prepare.err" \
    || { cat "$WORK/prepare.err" >&2; fail "游戏资源准备失败（日志：$WORK）"; }

echo '正在导入游戏资源'
"$GODOT" --headless --path main --editor --import >"$WORK/import.log" 2>"$WORK/import.err" \
    || { tail -20 "$WORK/import.err" >&2; fail "游戏资源导入失败（日志：$WORK）"; }

echo '正在进入主菜单'
export TURN_STARTUP_READY_FILE="$READY"
"$GODOT" --path main --log-file "$GAME_LOG" "$@" &
GAME_PID=$!
unset TURN_STARTUP_READY_FILE

# Wait for the menu to signal readiness (or for the game to die trying).
deadline=$((SECONDS + 45))
while [ ! -e "$READY" ] && [ "$SECONDS" -lt "$deadline" ]; do
    kill -0 "$GAME_PID" 2>/dev/null || break
    sleep 0.1
done

if [ ! -e "$READY" ]; then
    if ! kill -0 "$GAME_PID" 2>/dev/null; then
        wait "$GAME_PID"
        fail "未能进入游戏主菜单（日志：$WORK）"
    fi
    echo "警告：45 秒内未收到主菜单就绪信号，游戏仍在运行（日志：$WORK）" >&2
else
    # Startup handoff done: drop logs the game no longer needs.
    rm -f "$READY" "$WORK/prepare.log" "$WORK/prepare.err" "$WORK/import.log" "$WORK/import.err" "$GAME_LOG"
    rmdir "$WORK" 2>/dev/null || true
fi

wait "$GAME_PID"
