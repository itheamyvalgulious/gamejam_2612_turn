# Turn · 人形机甲刀客

人形近战精英的独立 Godot 4.7.2 工程，使用 Forward+ 渲染。跟随玩家视线格挡，玩家可从画面外用刀弧命中。首次进入 20 米内会触发一次低位蓄力和突进二连斩，之后接入警戒、追击及普攻。

## 打开工程

在 Godot 项目管理器导入本目录的 `project.godot`。按 **F5** 进入展台，左键拖动环绕，滚轮缩放。

| 要看什么 | 入口 |
| --- | --- |
| 模型和持刀踱步 | `scenes/duelist/duelist_preview.tscn` |
| 开场二连斩动作演示 | 在编辑器打开 `scenes/duelist/duelist_demo.tscn`，按 **F6** |
| 第一人称实战 | 在本目录运行下方命令 |

```sh
godot --path . res://main.tscn -- --duelist
```

如果终端找不到 `godot`，把命令开头换为本机 Godot 4.7.2 的可执行文件路径。首次运行命令前，可以先用编辑器打开工程完成导入。

实战中点击画面接管视角。WASD 移动，左键攻击，右键架刀，R 重开，Esc 暂停并释放鼠标。动作演示中可用 V 慢放、Tab 定格。

## 角色资源和行为

- 模型入口是 `scenes/duelist/duelist_model.tscn`，机体、刀、关节和甲片实现在 `src/enemies/duelist/`，专用材质在 `gfx/`。
- 实战由 `src/game/enemy_duelist.gd` 接入。开场蓄力只触发一次，巡战随后在近身二连斩、直刺接横扫、三刀冲刺斩之间选择。
- 普攻先亮红并用约 0.3 秒举刀，最后一刀结束后恢复蓝光。架住首刀不会打断后续连段。
- [横扫挥斩动作拆解](docs/横扫挥斩动作拆解.md) · [开场两段连招设计](docs/人形刀客两段连招方案.md)

基础四足主角、操作与对照关卡可见 [基础动作原型](../../../levels/actdemo/README.md)。
