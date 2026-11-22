# SCENE LAB // 仓库 · 回廊 · 病房

三个**纯场景**试验关：没有敌人，用来验证场景尺度、走位、可跳平台和灯光。
引擎（`src/`、`gfx/`、字体）**整份复制自 `main/content/levels/actdemo`**，本工程只额外加了三个场景，
`main/content/levels/actdemo` 本身没有改动。

> 引擎层面的设计说明（攻击/格挡/读招/音频/视线判定等）见 **`main/content/levels/actdemo/README.md`**，这里不再重复。

## 三个场景

| 关 | 场景 | 尺寸 | 可跳上的东西 |
| --- | --- | --- | --- |
| 4 | **仓库**（货架迷宫 + 集装箱 + 天车） | 56 × 36 × 13.5 m | 货架每层、集装箱顶、装卸台 |
| 5 | **回廊实验舱**（圆形大厅 + 中央玻璃罐 + 环形长廊） | R = 30 m，层高 14 m | 罐体外圈管线、检修台 |
| 6 | **病房 · 夜班**（30 张床 + 中央岛 + 吊顶帘轨 + 整面镜墙） | 40 × 22 × 6.5 m | 床 0.59 / 床头柜 0.75 / 护士站 1.05 / 处置柜与隔墙 1.30 m |

病房的隔帘是**固定随机**：床与床之间全拉、床与过道之间按哈希挑一部分拉满；
东门对面是一面 12 × 4.56 m 的**真平面镜**（`src/ward/mirror.gd` + `gfx/ward/mirror.gdshader`）。

## 运行

```bash
./run.sh -- --warehouse     # 第 4 关 · 仓库
./run.sh -- --panopticon    # 第 5 关 · 回廊实验舱
./run.sh -- --ward          # 第 6 关 · 病房
./run.sh                    # 不带参数从第 1 关（原 actdemo 的窄巷）开始
```

引擎不在 PATH 里时用 `GODOT_BIN=/path/to/godot ./run.sh`。

`R` 重开本关、`N` 下一关，可以在第 1–6 关之间循环。

## 操作

| 输入 | 功能 |
| --- | --- |
| `WASD` + 鼠标 | 移动 / 视角 |
| `空格` | 跳跃 |
| `Shift` | 冲刺 |
| 鼠标左键 | 攻击 |
| 鼠标右键 | 架招 / 弹反 |
| `V` / `Tab` | 切第三人称 / 第一人称 |
| `Esc` | 暂停 |

## 目录

```
src/warehouse/   warehouse_arena.gd + kit.gd（共享建模工具）+ occlusion.gd
src/panopticon/  panopticon_arena.gd
src/ward/        ward_arena.gd + mirror.gd
gfx/warehouse/   仓库材质（floor / surface）
gfx/panopticon/  回廊材质（floor / liquid），病房地面也在用 floor
gfx/ward/        镜面 shader
src/...          其余为 actdemo 引擎原件
```

## 已知限制

- 三关都是 0 敌人，`Level` 的 `clear` 只在敌人全灭时触发，所以**正式流程里不会自动过关**；
  用 `N` 手动切关，或直接用上面的参数进关。
- 病房的镜子会多渲染一遍场景（`SubViewport` 640×360），开销大约 +30% 的 GPU 绘制。
