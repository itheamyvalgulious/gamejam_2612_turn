# 关卡公共组件

[仓库](../warehouse/README.md)、[回廊实验舱](../panopticon/README.md)和[病房 · 夜班](../ward/README.md)共用玩家控制、相机、界面、音效、建模工具和部分材质。关卡入口、地图和专用材质在各自目录。

`main/tools/prepare_game.py` 构建时将公共脚本和每个关卡的入口接进同一个 TURN 工程。修改后从 [游戏工程](../../../project.godot) 的「关卡选择」预览对应关卡。
