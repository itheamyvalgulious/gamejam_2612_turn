# Cargo Hold2 · 相位伏击

独立 Godot **4.7.2 / Forward+** 工程，入口为 `scenes/cargo_hold2/project.godot`。用 Godot 导入该文件，等待资源导入完成后按 **F5**，即可进入货舱关卡。不需要打开 ACT demo，也不需要单独运行 `src/cargo_hold2/` 中的脚本。

`project.godot` 是工程配置入口；游戏逻辑、场景与资源按仓库惯例分开存放。

## 文件结构

```text
cargo_hold2/
├── project.godot           # 独立工程配置与自动加载项（autoload）
├── main.tscn               # 默认启动场景
├── src/
│   ├── main.gd             # 货舱游戏主循环
│   ├── cargo_hold2/        # 环境、关卡编排、碰撞、敌人和相位特效
│   ├── core/              # 参数、输入、命中与视野判定
│   ├── game/              # 战斗基础类、玩家、相机与 HUD
│   ├── vesper/            # 程序化四足机甲
│   ├── arena/             # 基础类依赖的场景构建组件
│   ├── city/              # 程序化建模与材质组件
│   ├── audio/             # 声音
│   ├── fx/                # 特效
│   └── ui/                # 参数与操作面板
├── gfx/                   # shader；货舱材质位于 cargo_hold2/ 子目录
├── assets/fonts/          # 沿用 demo 的字体
├── run.cmd                # Windows 双击启动入口
├── run.ps1                # Windows 自动导入与启动脚本
├── run.sh                 # Bash 启动入口
└── README.md
```

## 运行

Windows 下双击 `run.cmd`，会自动补齐字体和脚本导入后进入游戏。在工程目录的 PowerShell 中运行以下命令可打开编辑器：

```powershell
.\run.cmd -Editor
```

引擎路径可以通过环境变量 `GODOT_BIN` 或启动参数 `-GodotPath` 指定：

```powershell
.\run.cmd -GodotPath 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe'
```

也可以手动导入后直接启动：

```powershell
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path 'D:\gamejam_2612_turn\scenes\cargo_hold2' --import --quit
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --path 'D:\gamejam_2612_turn\scenes\cargo_hold2'
```

Bash 启动方式：

```bash
cd scenes/cargo_hold2
./run.sh
```

首次启动必须完成资源导入。`project.godot` 是工程入口，`.godot/` 是可重建的缓存目录，不需要提交到 Git。

## 环境与材质

货舱尺寸为 **80 × 60**，顶高 **16**，均为 demo 世界单位。场景内已去除文字标签，舱壁百叶、检修盖、地面格栅与顶棚线槽使用实体几何。

集装箱采用 **512 × 512、带 mipmap 的切线空间法线贴图**，由 `src/cargo_hold2/container_normal.gd` 在运行时生成并共享。细小波纹由法线贴图表现，边框、包角、锁杆与加强筋保留实体结构。

实体与霓虹更新：修复 MeshKit 倒角边条的位置偏移及角部闭合，去除原点附近的错位黑线。集装箱增加封闭内芯、加厚双开门、凸起加强筋、铰链锁扣；碰撞外沿包含新增结构。墙边、通道边缘及顶棚增加缓慢流动的青色、紫色激光灯管，灯具支架保持在顶棚服务层。

灯条配置局部光源，照亮附近墙面、地板与箱体；环境底光降低，以保留暗色货舱氛围。HUD 的中央标题、副标题和战斗提示按实际文字宽度居中。
