# TURN 项目工作约定

- 在用户电脑上验证 Godot 项目时默认使用 --headless。
- 需要截图时使用独立桌面，并在游戏参数里传入 -- --no-mouse-capture。先确认工程支持该参数，确认前仅做无窗口验证。
- 玩家亲自试玩时由玩家点击游戏画面接管视角。自动验证不点击接管，也不移动系统光标。
- 团队素材与源码在 `main/content/` 按用途维护。`main/runtime/` 由 `main/tools/prepare_game.py` 重建。
