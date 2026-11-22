# gamejam_2612_turn

2026 年 12 月 Game Jam 的统一仓库：各子工程均为 **Godot 4.7.2 纯代码程序化**工程，
零外部模型、零位图贴图（材质一律是写进 shader 的数学函数）。

| 目录 | 内容 | 一句话 |
| --- | --- | --- |
| `basic/` | 三个玩法原型 | ACT 四足刀客、VESPER 程序化主角、3×3 程序化地图/场景 |
| `character_design/` | 敌人与武器角色工程 | ARC Sentinel、Shard Phantom、Boss Leviathan、少女头部、电弧剑 |
| `main/` | 主程序预留目录 | 用于后续主程序整合 |
| `scenes/` | 场景试验（无战斗） | 仓库 / 回廊实验舱 / 病房 / Cargo Hold2 / 霓虹街区 / Galleria |

各目录的详细能力范围、参数开关与调参说明见各自目录下的 `README.md`。

## basic

| 目录 | 项目 | 一句话 |
| --- | --- | --- |
| `basic/actdemo/` | ACT // 四足刀客 | 四足机甲、武士刀、赛博朋克巷战的动作 demo，「看见就打不到 / 看见就会死」的视线博弈 |

| `basic/mapbuilder/` | 程序化地图/场景探索 | 3 个任务（赛博城市 / 自然地形 / 宇宙飞船）× 3 个模型的 9 个独立交付，初稿冻结在 `_baseline/` |

## character_design

| 目录 | 角色 | 定位 |
| --- | --- | --- |
| `character_design/hero/` | VESPER // VX-02 | 程序化四足高速 ACT 主角：4 次中心对称的噬菌体式机械腿 + 人形战斗底盘 + 激光大剑 |
| `character_design/arc_sentinel/` | ARC // SENTINEL v3 | 普通近战小怪 · 三角履带炮塔 |
| `character_design/shard_phantom/` | SHARD // PHANTOM | 位移敌人 · 模块化悬浮人形 |
| `character_design/boss/` | LEVIATHAN // ABYSSAL WARDEN | 最终 Boss · 机械章鱼 |
| `character_design/weapon_electricity_sword/` | 电弧剑 | 电弧场 / ribbon 独立资产 |
| `character_design/_kit_template/` | 套件模板 | 新建角色工程的共享骨架 |

三个敌人工程共享同一套「暗黑舞台 + 霓虹轮廓光 + ACES/Bloom/SSAO + 扫描线暗角」
的呈现体系，与 `basic/actdemo`、`character_design/hero` 同一画风家族。

## scenes 独立关卡

三个关卡各自包含完整的 Godot 工程、字体和启动脚本。Windows 双击对应目录内的 `run.cmd`；也可导入其 `project.godot`，等待资源导入完成后按 F5。

| 目录 | 场景与玩法 | 敌人 |
| --- | --- | --- |
| [scenes/cargo_hold2](scenes/cargo_hold2/README.md) | 集装箱掩体、固定点位激光位移 | 3 位移 + 1 基础 |
| [scenes/city](scenes/city/README.md) | 夜间赛博街区、三路绕侧、实体店铺与车辆掩体 | 3 基础 + 2 远程 + 1 位移 |
| [scenes/galleria](scenes/galleria/README.md) | 高台跃下、空中左键坠击、下层中庭与返程阶梯 | 4 基础 + 2 远程 |

两个新关卡沿用 Cargo Hold2 的角色、输入、美术和独立启动管线，均以肃清当前区域为通关条件。Galleria 从高台下落时按左键可发动落地范围攻击。详见各关卡 README。

## scenes 场景试验

纯场景、无敌人，用来验证尺度、走位、可跳平台与灯光；不做通关判定，用 `N` 手动切关。
每个目录同样是完整的 Godot 4.7.2 工程，`./run.sh -- --<场景名>` 直接进对应场景。

| 目录 | 场景 | 看点 |
| --- | --- | --- |
| [scenes/scene_lab](scenes/scene_lab/README.md) | 仓库 / 回廊实验舱 / 病房 | 货架与箱顶攀爬、圆形场地边界、30 张病床 + 中央隔墙 + 12×4.56 m 平面镜 |

## 运行

需要 Godot **4.7.2**（`godot` 在 `PATH` 里，或改各 `run.sh` 里的路径）。

```bash
cd scenes/cargo_hold2 && ./run.sh                 # 独立货舱关卡
cd basic/actdemo    && ./run.sh                 # 游戏本体
cd character_design/hero && ./run.sh            # 展示循环，按任意移动/攻击键接管
cd basic/mapbuilder/t3_spaceship/ds41-1017-max && ./run.sh   # 任选一格，9 格都是独立工程

cd character_design/arc_sentinel  && ./run.sh
cd character_design/shard_phantom && ./run.sh
cd character_design/boss          && ./run.sh
```

`mapbuilder` 的每一格、`character_design` 的每个角色都是可独立打开的 Godot 工程；
首次打开若出现 `class_name` 未注册，先执行一次 `godot --headless --path . --import`。

## 生成物不入库

按「源码能直接生成的一律不入库」的约定，以下内容被根目录 `.gitignore` 排除，
随时可由源码重建（文件仍保留在本地磁盘）：

| 路径 | 重建方式 |
| --- | --- |
| `**/.godot/` | 打开工程时自动重建（`godot --headless --path . --import`） |
| `basic/actdemo/build/` | `./web/build_web.sh build_all`（Web / Windows / macOS 三端导出） |
| `basic/actdemo/shots/` | `DISPLAY=:0 godot --path . res://scenes/shots.tscn` |
| `**/renders/` | 各工程 `scenes/*shots.tscn`、`render_stills.tscn` / `render_movie.tscn` 等渲染场景 |
| `basic/mapbuilder/t3_spaceship/*/baked/` | `./bake.sh`（`godot --path . -- --bake`） |
| `basic/mapbuilder/t3_spaceship/qwen38-max/cache/` | 首次运行按 `scripts/main.gd` 的缓存逻辑生成 |
| `basic/mapbuilder/t2_terrain/ds41-1017-max/assets/` | `python3 tools/gen_textures.py`、`gen_rockface.py --tex --mesh`、`gen_waterfall.py`（需 numpy + Pillow） |
| `basic/actdemo/web/dev_*.pem` | 本地自签 TLS 证书，`openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout dev_key.pem -out dev_cert.pem -subj "/CN=localhost"` |
| `_backup_nested_git/` | 旧嵌套 git 仓库的 bundle 备份，仅留本地 |

调试截图（各项目的 `shots/`、`screenshots/`）与编辑器缓存已从仓库移除，
统计层面的取舍见上表。
