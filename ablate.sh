#!/bin/bash
# 单关 ablate 归因：./ablate.sh <level> [ablate1,ablate2,...]
LV="${1:-4}"
OUT=/tmp/opencode/perf60/abl-L$LV
mkdir -p "$OUT"
cd /tmp/opencode/turn-perf60
for ab in none msaa post gi probe shadows particles enemies lights; do
  EXTRA=""
  [ "$ab" != "none" ] && EXTRA="--ablate=$ab"
  echo "=== L$LV ablate=$ab $(date +%H:%M:%S) ==="
  flock /tmp/opencode/turn-gpu.lock -c \
    "cd /tmp/opencode/turn-perf60 && DISPLAY=:10 timeout 90 godot --path main -- \
      --play-bench --level=$LV --keep-enemies=1 --warmup=2 --measure=4 \
      $EXTRA --report=$OUT/$ab.json -- --no-mouse-capture" 2>&1 | grep -E "RESULT|SPIKE" | head -6
done
echo "=== ablate summary L$LV ==="
python3 - "$OUT" <<'EOF'
import json,sys,glob,os
for f in sorted(glob.glob(sys.argv[1]+"/*.json")):
    r=json.load(open(f)); s=r["stats"]; n=os.path.basename(f)[:-5]
    print("%-10s fps=%4.0f p50=%4.1f p95=%4.1f gpu=%4.1f/%4.1f node=%4.1f gap=%4.1f" % (
        n, s["fps_avg"], s["p50_ms"], s["p95_ms"],
        s.get("gpu_p50_ms",0), s.get("gpu_p95_ms",0),
        s.get("node_process_p50_ms",0), s.get("post_process_gap_p50_ms",0)))
EOF
