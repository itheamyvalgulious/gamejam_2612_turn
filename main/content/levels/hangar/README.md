# 三号船坞（空间样段）

76 × 68 × 27 m 的室内船坞：系留甲板 + 30 m 转盘、北侧维修舱（空检修位）、
南侧勤务舱（储罐隔间）、东侧舰载机大门、东南人员气闸、北墙悬挑控制台。

**这是空间样段**：验证走位、镜头、净空和空间可读性，不是最终美术，
也没有接 Boss、没有敌人、不推进关卡状态。

方案与图纸：`projects/game-jam-turn/docs/HANGAR_PLAN.md`、
`docs/hangar_layout_v2.svg`（本地，不随工程分享）。

## 从哪进

主工程 `main/` 的关卡选择里选「三号船坞」。也可以直接起这一关：

```bash
cd main
python3 tools/prepare_game.py
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
~/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## 走一遍

出生在西侧走廊（外门锁死）→ 沿地面黄色走道往东 → 北侧走道能看到空检修位、轴架和工具区 →
东侧走道转向南 → 东南角绿灯的 `AIRLOCK` 就是人员出口。

- `--rings`：叠加 15 / 21.4 / 25 m 三个参考圆，便于核对 Boss 包络与安全环。
- 甲板中央是 Boss 占位：4 m 球体、体心 y=6、8 条 15 m 腿，只作尺度参照，不参与战斗。

## 已知边界

- 本关没有敌人，`LevelUnit` 不会进 `clear`；走到气闸只是空间终点。
- 舰载机大门是关着的（只走舰载机），不是隐形墙。
- 外墙、储罐、柜体用圆形掩体近似阻挡，和引擎的解析碰撞一致；
  门洞按 4–5 m 留净宽。


## 二阶段投影（场景侧）

组员反馈：Boss 二阶段会看不到 Boss。本关为此预留了「一侧墙 + 射灯投影」：

- 东侧舰载机大门内侧挂了一块 **28 × 13.8 m 哑光投影幕**（带钢框），
  挡住门筋，作为影子承接面。
- 西门内侧（偏南）一盏 **投影射灯**（`Phase2Spot`，13°、带阴影），
  把中央 Boss 的影子斜投到幕上；影子会落在 Boss 右侧，玩家在正面也能看到。
- 常规模式下投影灯关闭；二阶段时：

```gdscript
var arena := ...   # LevelUnit 里拿到的 arena 字典
arena["phase2"].set_phase2(true)    # 关常规灯 + 只留投影灯 + 环境光 0.09
arena["phase2"].set_phase2(false)   # 恢复
```

实现：`src/arena/hangar_phase2.gd`，收集所有灯光与顶灯灯具，
切换时统一隐藏；环境光由 `WorldEnvironment` 直接改。**什么时候切由 Boss 流程决定**，
场景侧只保证切过去之后能看。

本地预览：启动参数加 `-- --phase2`（`hangar_arena.gd` 会读取）。
