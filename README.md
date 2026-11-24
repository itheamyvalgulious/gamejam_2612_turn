# TURN

团队交付统一放在 `main/content/`，按关卡、敌人、主角、武器、地图和模板归档。每份交付和它的模型、动作、材质、说明及验证场景放在一起。未接入正式关卡的敌人也收在敌人分类下。

## 文件结构

[查看 main 的分层目录说明](main/docs/project_layout.md)。

| 目录 | 内容 |
| --- | --- |
| `main/content/levels/` | 霓虹窄巷、雨夜广场、灯墙之厅、货舱 02、霓虹街区、坠击中庭、仓库、回廊实验舱、病房和三号船坞的源文件 |
| `main/content/enemies/mobs/` | [人形刀客](main/content/enemies/mobs/mech_duelist/README.md)、[ARC Sentinel](main/content/enemies/mobs/arc_sentinel/README.md)、[单轮巡射机甲](main/content/enemies/mobs/wheel_sentry/README.md)、[Shard Phantom](main/content/enemies/mobs/shard_phantom/README.md) |
| `main/content/enemies/bosses/` | [折相](main/content/enemies/bosses/phase_boss/README.md)、[Leviathan](main/content/enemies/bosses/leviathan/README.md) |
| `main/content/characters/` | [VESPER 主角](main/content/characters/vesper/README.md) |
| `main/content/weapons/` | [电弧剑](main/content/weapons/electric_sword/README.md) |
| `main/content/maps/` | [城市、地形、飞船地图实验](main/content/maps/README.md)及 `_baseline/` 历史初稿 |
| `main/content/templates/` | [敌人设计套件](main/content/templates/enemy_design/README_kit.md) |
| `main/assets/ui/`、`main/ui/` | 菜单背景、关卡缩略图、菜单和选关界面 |
| `main/core/`、`main/tools/` | 游戏会话、关卡目录和资源构建工具 |
| `main/runtime/` | 构建生成的运行资源，按关卡、敌人、音效、角色、着色器和界面分目录 |
| `main/docs/`、`main/build/` | [敌人设计说明](main/docs/enemy_design.md)与发行文件 |

### 正式关卡源文件

| 关卡 | 维护位置 |
| --- | --- |
| 霓虹窄巷、雨夜广场 | [levels/actdemo](main/content/levels/actdemo/README.md) |
| 灯墙之厅 | [levels/shadow_chamber](main/content/levels/shadow_chamber/README.md) |
| 货舱 02 | [levels/cargo_hold2](main/content/levels/cargo_hold2/README.md) |
| 霓虹街区 | [levels/city](main/content/levels/city/README.md) |
| 坠击中庭、坠击中庭 · 高低差 | [levels/galleria](main/content/levels/galleria/README.md) |
| 仓库 | [levels/warehouse](main/content/levels/warehouse/README.md) |
| 回廊实验舱 | [levels/panopticon](main/content/levels/panopticon/README.md) |
| 病房 · 夜班 | [levels/ward](main/content/levels/ward/README.md) |
| 三号船坞 | [levels/hangar](main/content/levels/hangar/README.md) |

仓库、回廊实验舱、病房和三号船坞的玩家控制、界面与公用材质工具放在 [levels/shared](main/content/levels/shared/README.md)。十一个关卡都从「关卡选择」进入。仓库、回廊实验舱、病房和三号船坞暂未配置敌人，可停留走动，按 **N** 继续到下一关，或按 **F1** 返回选关。

各关卡自带的合成音效源码在对应关卡的 `src/audio/`，构建时归到 `main/runtime/audio/`。编辑请从 `main/content/` 的原件开始。正式关卡使用 `main/project.godot` 启动。敌人与其他独立素材可以用各自的 `project.godot` 预览。

十一个关卡共用 [VESPER v2](main/content/characters/vesper/README.md) 的机体、武器和动作。主角修改提交到 `main/content/characters/vesper/`，关卡自己的按键、相机和战斗参数随该关卡维护。

## 正式关卡敌人

| 敌人 | 关卡中的数量和用途 |
| --- | --- |
| ARC Sentinel | 12，基础近战小兵 |
| 单轮巡射机甲 | 6，远程射手 |
| Shard Phantom | 4，替换货舱和街区的相位位移怪 |
| 人形刀客 | 1，坠击中庭 · 高低差，可试验击倒慢放 |
| 折相 | 1，灯墙之厅首领 |

Leviathan 的素材在敌人目录中供后续关卡使用。构建工具提取各关卡需要的敌人依赖。普通敌人使用原设计工程的模型、动画和专用脚本，折相使用自身的完整战斗控制器。

## 后续提交素材

按素材最终在游戏里的用途提交源码。更新已有内容时，修改对应的现有目录。新增内容时，在对应类别下用小写英文和下划线建立单独目录。

| 要提交的内容 | 放置位置 |
| --- | --- |
| 可玩的关卡、布光、碰撞、出生点和刷怪配置 | `main/content/levels/<关卡名>/` |
| 普通或精英敌人、Boss | 小兵和精英放 `main/content/enemies/mobs/`，Boss 放 `main/content/enemies/bosses/`，每个敌人占一个目录 |
| 多个敌人共用的战斗接口或工具脚本 | `main/content/enemies/shared/` |
| 主角模型、骨架、动作与材质 | `main/content/characters/<角色名>/` |
| 独立武器的模型、动作和特效 | `main/content/weapons/<武器名>/` |
| 地图试验、原型和历史方案 | `main/content/maps/` 下对应主题的目录 |
| 关卡内合成音效 | 对应关卡的 `src/audio/` |
| 音频文件、贴图和其他原始素材 | 使用它们的关卡、敌人或角色目录中的 `assets/`，录制音频放在 `assets/audio/` |
| 主菜单背景、关卡缩略图和菜单代码 | 图片放 `main/assets/ui/backgrounds/` 或 `main/assets/ui/level_previews/`，菜单代码放 `main/ui/menu/` |

每份交付把模型、动作、着色器、引用资源和预览场景放在同一目录。随素材提交或更新 `README.md`，写明预览入口、依赖和接入的关卡。未接入关卡的敌人也放在相应的敌人类别下。

- **调整现有关卡的刷怪**：改该关卡的源文件。新增正式关卡时，同时更新 `main/tools/prepare_game.py` 和 `main/core/level_catalog.gd`。
- **把新敌人接入游戏**：更新关卡中的刷怪入口，并在 `main/tools/encounter_roster.py` 中声明共享模型和控制器依赖。关卡专用的接入脚本随关卡维护，敌人自身的模型和动作随敌人维护。
- **提交和验证**：从最新 `main` 建分支，使用项目内相对路径，保留 Godot 资源的 `.uid` 和导入设置。运行下方构建命令，打开受影响的关卡或预览，然后发起合并请求，写明素材路径和验证结果。
- **生成目录**：`main/runtime/`、`main/build/`、`.godot/` 和 `__pycache__/` 由本地工具生成。提交源文件即可，试玩包单独分发。

## 运行和导出

Windows 双击 `main/build/Turn.exe`。游戏默认全屏，按 **F11** 切换全屏与窗口，关卡内按 **F1** 返回选关。

从仓库根目录运行下列命令。需要 Python 3、Godot 4.7.2 和同版本的 Windows 导出模板。

```powershell
python main/tools/prepare_game.py
godot --headless --path main --import
godot --path main

# 导出时执行以下两行
New-Item -ItemType Directory -Force main/build
godot --headless --path main --export-release Windows build/Turn.exe
```

`main/runtime/`、`main/build/` 和 Godot 缓存都是本地生成目录。分享 Windows 试玩版时发送 `Turn.exe` 即可。
