#!/bin/bash
# 11 关串行基准：每关 warmup 2s + measure 5s，keep-enemies 默认 1（模拟真实负载）。
# 用法: ./bench_all.sh <tag> [extra args...]
# 结果: /tmp/opencode/perf60/<tag>/L<n>.json + logs
set -u
TAG="${1:-base}"
shift || true
OUT=/tmp/opencode/perf60/$TAG
mkdir -p "$OUT"
cd /tmp/opencode/turn-perf60
for lv in 0 1 2 3 4 5 6 7 8 9 10; do
  echo "=== L$lv ($(date +%H:%M:%S)) ==="
  flock /tmp/opencode/turn-gpu.lock -c \
    "cd /tmp/opencode/turn-perf60 && DISPLAY=:10 timeout 120 godot --path main -- \
      --play-bench --level=$lv --keep-enemies=1 --warmup=3 --measure=6 \
      --screenshot=$OUT/L$lv.png --report=$OUT/L$lv.json $* \
      -- --no-mouse-capture" 2>&1 | grep -E "RESULT|opening|warmup|error|ERROR|SCRIPT" | head -8
done
echo "=== summary $TAG ==="
for lv in 0 1 2 3 4 5 6 7 8 9 10; do
  python3 - "$OUT/L$lv.json" <<'EOF'
import json,sys
try:
    r=json.load(open(sys.argv[1]))
    s=r["stats"]
    print("L%-2d %-14s fps=%5.1f p50=%5.1f p95=%5.1f max=%6.1f gpu=%4.1f/%4.1f setup=%4.1f gap=%4.1f game=%4.1f | tex=%s vp=%s scale=%s" % (
        r["level_index"], r["level"], s["fps_avg"], s["p50_ms"], s["p95_ms"], s["max_ms"],
        s.get("gpu_p50_ms",0), s.get("gpu_p95_ms",0), s.get("render_setup_p50_ms",0),
        s.get("post_process_gap_p50_ms",0), s.get("game_process_p50_ms",0),
        r.get("texture_size","?"), r.get("viewport_size","?"), r.get("scaling_3d_scale","?")))
except Exception as e:
    print(sys.argv[1], "FAIL", e)
EOF
done
