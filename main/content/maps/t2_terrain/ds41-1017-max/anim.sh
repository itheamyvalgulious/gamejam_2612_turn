#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:0}"
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f .godot/uid_cache.bin ]; then
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
mkdir -p screenshots/anim
godot --path . -- --anim=detail_water --size=960x540 --res=768
godot --path . -- --anim=waterfall_20m --size=960x540 --res=768
ffmpeg -y -framerate 30 -i screenshots/anim/detail_water_%03d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -vf scale=960:540 screenshots/water_flow.mp4 >/dev/null 2>&1
ffmpeg -y -framerate 15 -i screenshots/anim/detail_water_%03d.png \
  -vf "scale=420:236:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
  screenshots/water_flow.gif >/dev/null 2>&1
ffmpeg -y -framerate 30 -i screenshots/anim/waterfall_20m_%03d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -vf scale=960:540 screenshots/waterfall.mp4 >/dev/null 2>&1
rm -rf screenshots/anim
echo "videos written"
