#!/usr/bin/env bash
# =============================================================================
# 构建/伺服 ACT 四足刀客
#
# Web 导出必须用 Compatibility(GLES3/WebGL2) 渲染器，桌面版用 Forward+；
# 所以脚本先临时改 project.godot 导出 Web，再还原后导出 Windows/macOS。
#
#   ./web/build_web.sh                    # 只构建 Web -> build/web/
#   ./web/build_web.sh build_all          # Web + Windows + macOS
#   ./web/build_web.sh --serve            # 构建 Web 后起服务（127.0.0.1:16374）
#   ./web/build_web.sh build_all --serve  # 全部构建后起服务
#   ./web/build_web.sh serve              # 不构建，直接伺服已有产物
#
# 服务路径：/ = 网页版游戏，/win、/mac = 桌面版压缩包下载
# 环境变量：GODOT_BIN 指定 godot 可执行文件
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
OUT="$PROJ/build/web"
WIN_DIR="$PROJ/build/win"
MAC_DIR="$PROJ/build/mac"
WIN_EXE="ACT-Katana.exe"
WIN_ZIP="ACT-Katana-windows-x86_64.zip"
MAC_ZIP="ACT-Katana.zip"
GODOT="${GODOT_BIN:-godot}"
PORT=16374
BUILD_ALL=false
SERVE=false
BUILD=true

for arg in "$@"; do
    case "$arg" in
        build_all|build-all|--all) BUILD_ALL=true ;;
        --serve) SERVE=true ;;
        serve) SERVE=true; BUILD=false ;;
        --no-build) BUILD=false ;;
        --port=*) PORT="${arg#*=}" ;;
        -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "未知参数：$arg（--help 看用法）" >&2; exit 2 ;;
    esac
done

if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "找不到 godot：$GODOT（用 GODOT_BIN 指定）" >&2
    exit 1
fi

# ---- Web -------------------------------------------------------------------
build_web() {
    local BAK="$PROJ/project.godot.forward_bak"
    cp "$PROJ/project.godot" "$BAK"
    restore() { [ -f "$BAK" ] && mv "$BAK" "$PROJ/project.godot"; }
    trap restore EXIT

    python3 - "$PROJ/project.godot" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('renderer/rendering_method="forward_plus"', 'renderer/rendering_method="gl_compatibility"')
s = s.replace('renderer/rendering_method.mobile="gl_compatibility"', 'renderer/rendering_method.mobile="gl_compatibility"')
# Web 上关掉重度抗锯齿，保帧率
s = s.replace("anti_aliasing/quality/msaa_3d=2", "anti_aliasing/quality/msaa_3d=0")
open(p, "w", encoding="utf-8").write(s)
print("[web] project.godot -> gl_compatibility")
PY

    mkdir -p "$OUT"
    "$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1 || true
    "$GODOT" --headless --path "$PROJ" --export-release "Web" "$OUT/index.html"
    restore
    trap - EXIT

    # ---- 后置补丁 1：把 "Secure Context" 从硬失败改成警告 ------------------
    # Godot 网页壳要求 isSecureContext；但本项目是非线程构建（不用 SharedArrayBuffer），
    # 也不读麦克风/手柄，所以在局域网 http:// 下跑是安全的。这里降级为 console 警告，
    # 这样通过网关/局域网 IP 打开也能玩；想要真正的安全上下文请用 web/serve_web.sh --tls。
    python3 - "$OUT/index.js" <<'PY2'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
marker = "// [ACT demo] secure-context check relaxed"
if marker in s:
    print("[web] 已打过补丁，跳过")
    sys.exit(0)
old = """		if (!Features.isSecureContext()) {
			missing.push('Secure Context - Check web server configuration (use HTTPS)');
		}"""
new = """		if (!Features.isSecureContext()) { %s
			console.warn('[ACT] 非安全上下文：已跳过 Secure Context 检查（非线程构建不需要；麦克风/手柄可能不可用）。想要安全上下文请用 HTTPS。');
		}""" % marker
if old not in s:
    print("[web] 警告：没找到 Secure Context 检查块，未打补丁")
else:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("[web] Secure Context 检查已降级为警告")
PY2

    # ---- 后置补丁 2：非安全上下文下 AudioContext.audioWorklet 是 undefined --
    # audioWorklet 是 [SecureContext] 接口，http:// + 局域网 IP 时根本没有这个属性。
    # Godot 的 GodotAudio.init 里却无条件 `ctx.audioWorklet.addModule(...)`，
    # 于是页面报 "Cannot read properties of undefined (reading 'addModule')" 直接崩掉。
    # 加个守卫：没有 audioWorklet 就不加载位置上报 worklet（引擎本来就会退到
    # ScriptProcessorNode 的音频驱动），这样局域网 http 也能出声、能玩。
    python3 - "$OUT/index.js" <<'PY3'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
marker = "/* [ACT demo] audioWorklet guard */"
old = "GodotAudio.audioPositionWorkletPromise=ctx.audioWorklet.addModule(path);"
new = ("GodotAudio.audioPositionWorkletPromise="
       "ctx.audioWorklet?ctx.audioWorklet.addModule(path):Promise.resolve();" + marker)
if marker in s:
    print("[web] audioWorklet 守卫已存在，跳过")
elif s.count(old) != 1:
    print("[web] 警告：没找到 audioWorklet.addModule 调用，未打补丁")
else:
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("[web] audioWorklet 守卫已打补丁（非安全上下文退到 ScriptProcessor）")
PY3
}

# ---- 桌面版：此时 project.godot 已还原成 Forward+ ---------------------------
build_desktop() {
    mkdir -p "$WIN_DIR" "$MAC_DIR"

    echo "[win] 导出 Windows(x86_64) …"
    "$GODOT" --headless --path "$PROJ" --export-release "Windows Desktop" "$WIN_DIR/$WIN_EXE"
    python3 - "$WIN_DIR" "$WIN_ZIP" <<'PY'
import os, sys, zipfile
d, dst = sys.argv[1], sys.argv[2]
files = [f for f in sorted(os.listdir(d)) if not f.endswith(".zip") and os.path.isfile(os.path.join(d, f))]
with zipfile.ZipFile(os.path.join(d, dst), "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for f in files:
        z.write(os.path.join(d, f), f)
print("[win] %s <- %s" % (dst, ", ".join(files)))
PY

    echo "[mac] 导出 macOS(universal) …"
    "$GODOT" --headless --path "$PROJ" --export-release "macOS" "$MAC_DIR/$MAC_ZIP"
}

if [ "$BUILD" = true ]; then
    build_web
    if [ "$BUILD_ALL" = true ]; then
        build_desktop
    fi
fi

echo "[web] 产物："
ls -la "$OUT" | head -12
du -sh "$OUT"

if [ "$BUILD_ALL" = true ] || [ -f "$WIN_DIR/$WIN_ZIP" ]; then
    echo "[win] 产物："
    ls -la "$WIN_DIR"/*.zip "$WIN_DIR"/*.exe 2>/dev/null | sed 's/^/      /' || true
fi
if [ "$BUILD_ALL" = true ] || [ -f "$MAC_DIR/$MAC_ZIP" ]; then
    echo "[mac] 产物："
    ls -la "$MAC_DIR"/*.zip 2>/dev/null | sed 's/^/      /' || true
fi

if [ "$SERVE" = true ]; then
    exec "$HERE/serve_web.sh" --port="$PORT"
fi
