# 三号船坞（空间样段）

76 × 68 × 27 m 的室内船坞：系留甲板 + 30 m 转盘、北侧维修舱（穿梭机占位）、
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

出生在西侧走廊（外门锁死）→ 沿地面黄色走道往东 → 北侧走道能看到维修舱里的穿梭机 →
东侧走道转向南 → 东南角绿灯的 `AIRLOCK` 就是人员出口。

- `--rings`：叠加 15 / 21.4 / 25 m 三个参考圆，便于核对 Boss 包络与安全环。
- 甲板中央是 Boss 占位：4 m 球体、体心 y=6、8 条 15 m 腿，只作尺度参照，不参与战斗。

## 已知边界

- 本关没有敌人，`LevelUnit` 不会进 `clear`；走到气闸只是空间终点。
- 舰载机大门是关着的（只走舰载机），不是隐形墙。
- 外墙、储罐、穿梭机用圆形掩体近似阻挡，和引擎的解析碰撞一致；
  门洞按 4–5 m 留净宽。
