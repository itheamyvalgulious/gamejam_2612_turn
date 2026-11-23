#!/usr/bin/env bash
# 在 127.0.0.1:16374 上把网页版伺服起来
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/serve_web.py" "$@"
