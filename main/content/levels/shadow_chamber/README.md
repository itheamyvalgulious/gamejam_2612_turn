# 灯墙之厅

TURN 的第三个战斗关。用统一工程 `main/project.godot` 启动后，在选关中选择「灯墙之厅」。

- `main.tscn`、`src/main.gd` 和 `src/game/level.gd` 负责场景入口、玩家出生、开场和通关。
- `src/arena/` 和 `gfx/` 保存地图、墙面投影和关卡着色器。
- `src/game/enemy_phase_boss.gd` 负责绑定关卡碰撞、玩家伤害和 Boss 状态。折相的模型、动作和 AI 来自[敌人素材](../../enemies/boss/phase_boss/README.md)。

修改后从仓库根目录运行 `python main/tools/prepare_game.py`，再导入 `main/project.godot`。
