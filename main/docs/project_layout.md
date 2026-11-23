# TURN 工程目录

正式游戏从 `main/project.godot` 启动。团队交付以 `main/content/` 为主，菜单图片和界面分别维护在 `main/assets/ui/` 和 `main/ui/menu/`。调整源文件后运行 `python main/tools/prepare_game.py` 生成运行资源。

## main 第一层

| 路径 | 用途 |
| --- | --- |
| `project.godot` | TURN 的 Godot 项目入口，声明主菜单、全屏设置和全局会话 |
| `export_presets.cfg` | 正式工程的导出配置 |
| `content/` | 关卡、敌人、主角、武器、地图原型和设计模板的源文件 |
| `assets/ui/backgrounds/` | 主菜单背景图 |
| `assets/ui/level_previews/` | 正式关卡卡片的缩略图，文件名与关卡目录表中的图片名一致 |
| `ui/menu/` | 主菜单、选关界面、布局和交互 |
| `core/` | `level_catalog.gd` 管理正式关卡入口、顺序、标题和缩略图，`session.gd` 管理切关、返回选关和全屏切换 |
| `tools/` | `prepare_game.py` 收集素材并重写运行路径，`encounter_roster.py` 管理正式关卡使用的敌人依赖，`__pycache__/` 是 Python 缓存 |
| `docs/` | 项目目录说明和 [敌人动作与模型说明](enemy_design.md) |
| `runtime/` | 构建工具生成的 Godot 运行资源 |
| `build/` | 本地导出的试玩程序 |
| `.godot/` | Godot 导入和编辑器缓存 |

## content 的素材目录

| 一级目录 | 下一级目录及用途 |
| --- | --- |
| `levels/` | 每个独立地图或关卡模块拥有自己的入口、地图脚本、专用素材和 README |
| `enemies/` | `mobs/` 收普通和精英敌人，`bosses/` 收 Boss，`shared/` 收多个敌人共用的战斗接口 |
| `characters/` | `vesper/` 收主角场景、程序化模型、操控脚本和材质 |
| `weapons/` | `electric_sword/` 收电弧剑模型、材质、特效和预览场景 |
| `maps/` | `t1_city/`、`t2_terrain/`、`t3_spaceship/` 收地图原型，`_baseline/` 收这三组地图的历史初稿 |
| `templates/` | `enemy_design/` 收敌人制作可复用的场景、脚本和着色器模板 |

### 正式关卡

| 目录 | 关卡与内容 |
| --- | --- |
| `levels/actdemo/` | 霓虹窄巷和雨夜广场的原型关卡模块，两关由同一个模块生成 |
| `levels/shadow_chamber/` | 灯墙之厅，包含折相的战斗接入和场景灯墙 |
| `levels/cargo_hold2/` | 货舱 02，包含货舱地图、出生点和刷怪配置 |
| `levels/city/` | 霓虹街区，包含街道、掩体和敌人配置 |
| `levels/galleria/` | 坠击中庭，包含高低台地形、角色出生点和敌人配置 |
| `levels/warehouse/` | 仓库，独立入口、货架和装卸区地图、遮挡、地面材质 |
| `levels/panopticon/` | 回廊实验舱，独立入口、环廊和玻璃罐地图、液体材质 |
| `levels/ward/` | 病房 · 夜班，独立入口、病床与隔帘地图、平面镜 |
| `levels/shared/` | 仓库、回廊实验舱和病房共用的玩家、界面、音效和部分材质 |

关卡内的 `src/` 存场景脚本，`gfx/` 和 `shaders/` 存着色器，`assets/` 存贴图、字体和音频等资源。共享组件放在实际使用它们的公共目录。关卡独有的布光、碰撞、出生点和刷怪配置随关卡维护。

### 敌人

| 一级分类 | 角色目录 |
| --- | --- |
| `enemies/mobs/` | `arc_sentinel/` 是近战兵，`mech_duelist/` 是人形刀客精英，`wheel_sentry/` 是单轮远程兵，`shard_phantom/` 是相位位移兵 |
| `enemies/bosses/` | `phase_boss/` 是折相，`leviathan/` 是机械章鱼 Boss |
| `enemies/shared/` | 目前包含 `encounter_unit.gd`，定义多个敌人在关卡里共用的血量、受击和阵亡接口 |

每个敌人占一个同级角色目录。已有的 `src/` 或 `scripts/` 存模型、动作与行为代码，`scenes/` 存模型、预览和实战场景，`gfx/` 或 `shaders/` 存专用着色器，`assets/` 存模型依赖的原始素材，`data/` 存动作轨迹等数据。接入主工程的专用适配脚本随角色维护。ARC Sentinel 和 Shard Phantom 的主工程适配在各自的 `integration/`，由构建工具读取。单轮巡射机甲的主工程接入复用它自己的战斗脚本。

## runtime 的生成目录

| 路径 | 内容 |
| --- | --- |
| `levels/` | 正式关卡入口、运行场景与地图脚本，各独立关卡按所属模块存放 |
| `enemies/mobs/`、`enemies/bosses/` | 被正式关卡引用的敌人。每个角色的 `design/` 存模型、动作和技能依赖，`encounters/<关卡模块>/` 存接入该模块的脚本 |
| `enemies/shared/` | 普通敌人共用的战斗接口 |
| `characters/player/`、`characters/vesper/` | 各关卡使用的玩家控制器、相机、第一人称模型和机体骨架 |
| `systems/` | 按关卡模块组织的配置、按键、战斗判定、弹体与公共服务 |
| `audio/` | 按模块归档的音效入口和合成音源 |
| `fonts/` | 界面字体资源。其中 `shared/` 收共用字体文件 |
| `shaders/` | 正式关卡使用的材质与后处理着色器 |
| `ui/` | 关卡内 HUD、暂停和调试界面 |
| `vfx/` | 粒子、影子、命中反馈等特效脚本 |
| `media/` | 构建时按需生成，收需要进入正式游戏的其他媒体素材 |
| `.files.json` | 构建工具用于更新和清理生成资源的清单 |

提交时从源目录编辑，并更新对应的 README。`runtime/`、`build/`、`.godot/` 和 `__pycache__/` 由本地工具生成。新关卡的入口和顺序登记在 [关卡目录表](../core/level_catalog.gd)，要接入正式关卡的敌人依赖登记在 [敌人接入配置](../tools/encounter_roster.py)。
