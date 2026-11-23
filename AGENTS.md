# TURN 项目工作约定

- 在用户电脑上验证 Godot 项目时用独立桌面（DISPLAY :10，有真 GPU），并在游戏参数里传入 -- --no-mouse-capture。性能测试必须走真 GPU，不能只用 --headless。
- 玩家亲自试玩时由玩家点击游戏画面接管视角。自动验证不点击接管，也不移动系统光标。
- 团队素材与源码在 `main/content/` 按用途维护。`main/runtime/` 由 `main/tools/prepare_game.py` 重建。
