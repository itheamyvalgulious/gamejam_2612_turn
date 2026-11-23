#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export DISPLAY="${DISPLAY:-:10}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
exec godot --path . "$@"
