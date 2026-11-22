# 赛博朋克敌人角色工程

三个**独立可运行**的 Godot 4.7.2 角色工程，全部资产在运行时由代码生成：
没有任何外部网格、贴图、字体或音频。每个工程都能单独打开、旋转视角、
用场景内数值输入框实时调参、逐帧拖动时间轴检查动作。

| 目录 | 角色 | 定位 | 动画 | 视觉核心 |
| --- | --- | --- | --- | --- |
| [arc_sentinel](../content/enemies/melee/arc_sentinel/README.md) | **ARC // SENTINEL v3** | 普通近战小怪 · 三角履带炮塔 | idle / run / attack1 / attack2 / block | 两条钝角三角履带夹 0.52 m 立方体炮塔、半径=边长 1/3 的红色摄像头（内球旋转、外壳固定）、眼下一排闪烁状态灯、单条顶置三关节机械臂、黑色发射器 + 电弧闪电剑 |
| [shard_phantom](../content/enemies/phase/shard_phantom/README.md) | **SHARD // PHANTOM** | 位移敌人 · 模块化悬浮人形 | idle / walk / attack / disperse / reform | 大型相机镜头头、90 个独立模块与橙红推进器（背部/小腿/脚底悬浮喷口）、爆散重组、掌心手里剑 |
| [boss](../content/enemies/boss/leviathan/README.md) | **LEVIATHAN // ABYSSAL WARDEN** | 最终 Boss · 机械章鱼 | 8 条独立链式触手 · idle / support / attack1-3 / laser / 两阶段 | 2 m 半径装甲球、8 片滑动虹膜壳 + 连续孔径环、红色大摄像头眼、红色能量核心与透明约束层、20 m 低空 360° 横扫 |

三个工程共享同一套「暗黑舞台 + 霓虹轮廓光 + ACES/Bloom/SSAO + 扫描线暗角」
的呈现体系，与 [ACT](../content/levels/actdemo/README.md)、[VESPER](../content/characters/vesper/README.md) 同一画风家族。

## 刀客、单轮远程机甲与折相

以下三个目录各有独立的 Godot 4.7.2 工程与第一人称试玩关。用项目管理器导入各自的 `project.godot` 即可查看展台。各工程的说明包含实战入口和角色资源路径。

| 工程 | 内容 |
| --- | --- |
| [人形机甲刀客](../content/enemies/melee/mech_duelist/README.md) | 近战精英，含持刀踱步、开场蓄力二连斩、三套普攻和实战判定 |
| [单轮巡射机甲](../content/enemies/ranged/wheel_sentry/README.md) | 远程机甲，含轮组展台、走位、小束和长束的单怪实战 |
| [折相 Boss](../content/enemies/boss/phase_boss/README.md) | 重型四足机甲，含模型与动作展台、视野充能与虚化、侧跳后撤反击和实战演示关 |

---

## 快速开始

以下命令从仓库根目录执行，需要 **Godot 4.7.2**。本机 `DISPLAY=:10` 是可用 X 服务，Vulkan/Forward+ 正常。

```bash
cd main/content/enemies/melee/arc_sentinel   && ./run.sh      # 或 godot --path .
cd main/content/enemies/phase/shard_phantom  && ./run.sh
cd main/content/enemies/boss/leviathan           && ./run.sh
```

三个工程的默认主场景都是 `res://scenes/studio.tscn`。首次打开若出现
class_name 未注册，先执行一次：

```bash
godot --headless --path . --import
```

---

## 通用操作

| 输入 | 功能 |
| --- | --- |
| 鼠标左键/右键拖动 | 环绕相机 |
| 滚轮 | 推拉 |
| `F` | 重置机位 |
| `H` | 隐藏 / 显示 UI |
| `空格` | 播放 / 暂停 |
| `F12` | 保存截图到 `renders/` |
| 右侧面板 | `ANIM` / `PARAMS` / `JOINTS` / `INFO` 四个页签 |

`PARAMS` 与 `JOINTS` 里每一个数值都是真正的 `SpinBox`：可以直接键入数字，
也可以拖箭头步进；改几何参数会即时重建模型并保持当前姿势。`JOINTS` 页
可以只用单关节角度把角色摆成任意姿势，用来验证模型不是烘焙动画。

**ARC // SENTINEL v3**：`1`~`5` 播放 idle / run / attack1 / attack2 / block。攻击与格挡由解析机械臂 IK + 碰撞感知 swivel 求解，逐帧审计；block 的架式按威胁方向现场规划（11–20 ms，缓存后 0）。一次攻击/格挡不会中途取消，新请求排队到结束。

**SHARD // PHANTOM**：`1`~`5` 播放动画，`B` 闪烁（默认 5m）、`N` 散布后
自动重组、`M` 立即重组、`G` 切换「被注视即爆散」。角色顶部还有
BLINK / DISPENSE / REFORM 按钮与状态读数。

---

## ARC // SENTINEL v3

### 设定

**两条钝角三角履带夹着中间的立方体炮塔**，从立方体正上方伸出**一条**
三关节机械臂。只保留旧版的两个识别点：电弧闪电剑、正面红色摄像头。

- 履带：底边 1.0 m、高 0.394 m，顶角约 103°（钝角）；每侧 44 块独立
  履带板（黑色阳极氧化钢 + 两条防滑筋 + 铆钉，每 6 块一块橙色标记板）、
  开放式三角桁架、三个带辐条的角轮、后部张紧器、橡胶内衬。
- 身体：0.52 m 倒角立方体，底部炮塔环 + 固定腰柱；正面红色摄像头
  光学窗口半径 **0.173 m = 边长/3**，内部红色光球会旋转指向观察者，
  外部镜圈/玻璃罩**固定不转**；大眼下方 6 颗绿/橙/蓝状态灯独立闪烁；
  侧面散热槽与橙色装甲缝、背面电池包与电量条。
- 手臂：根部球关节 → 段 1（0.46 m）→ 肘球 → 段 2（0.40 m）→ 腕球 →
  全黑发射器 → 1.03 m 电弧剑。无刀鞘、无盾牌。
- 身高 **1.56 m**（到肩部球关节顶，不含机械臂）；履带外缘总宽 1.15 m。

### 动作

| clip | 长度 | 内容 |
| --- | --- | --- |
| `idle` | 3.20 s | 刀平举、略上翘指向前方，胳膊折叠；伺服呼吸、履带待机静止、光球追踪观察者 |
| `run` | 0.72 s | 车身前倾 + 颠簸；履带/车轮由独立驱动层按 2.0 m/s（可调至 3.0 m/s）滚动 |
| `attack1` | ~1.07 s | 正上方重砍：举到头顶（刀尖 2.81 m）→ 过顶下劈 → 刀尖落到身前 0.57 m 高 |
| `attack2` | ~1.16 s | 横扫：右后方 → 掠过正面 → 左后方，刀尖方位扫过约 479°，刀身保持水平 |
| `block` | 0.88 s | 路径规划的剑面格挡：刀身横切威胁射线、刀面正对来袭方向 |

所有单次动作从 idle 基准姿势出发、结尾混回同一姿势；一个动作不会中途取消。
履带与车轮是**独立于身体 clip 的运动层**：左右各按自己的地速积分，
轮角速度 `ω = v / wheel_r`，轮子转一圈履带正好走一个轮周长；因此
`set_track_speed(L, R)` 可以直接做差速转向，attack / block 时也能同时驱动。
block 的威胁方向改变时会现场规划：候选拦截位姿 → 解析 swivel IK →
全身审计 → 32 Hz 轨迹逐帧审计。首次规划实测 **11–20 ms**（8 个方向，
中位 ~15 ms），缓存后 0 ms；因此**不预烘焙**（v2 的 0.7 MB 轨迹表已删除）。
规划架式实测：威胁射线到刀身距离 0.0000 m、刀面误差 0.0°、整段最小净空 ≥ 0.043 m。

### 验收

`cd main/content/enemies/melee/arc_sentinel && godot --headless --path . res://scenes/qa.tscn` → **PASS（0 failures）**：
5 个 clip 逐帧自碰撞 + 地面、全部可达转场、attack1/attack2 姿态与扫掠角、
8 个威胁方向的 block（命中 / 刀面 / 净空 / 规划耗时）、光球追踪 0.00°、
外壳不转、履带-车轮物理耦合 / 差速 / 3 m/s 上限 / 与 body clip 解耦、
履带板运动方向、炮塔-履带间隙、6 颗状态灯闪烁。
逐项数字在 `arc_sentinel/renders/v3/qa_report.json`。

视觉：`DISPLAY=:10 godot --path . res://scenes/v3_details.tscn` 与
`res://scenes/v3_shots.tscn`，输出在 `arc_sentinel/renders/v3/`。

## SHARD // PHANTOM

### 设定与机制

悬浮的模块化人形：约 1.60m 高、悬浮 0.20m，身体由 60–90 个独立机械模块
（默认 90）围绕一圈圈拼成，每个模块都有橙红色微型推进器；内部有近黑骨架
维持形体。头部是单个大型凹陷相机镜头（深筒、光圈环、暗腔、遮光罩，
橙红虹膜，随头部关节转向），没有人脸/嘴/V 缝。双手是掌心发射器。
悬浮主推力来自背部 2 个大喷口、后小腿 2 个、脚底 2 个（胯下无喷口），
配向下的舞台光洗与地面光池。模块是独立部件，头部/身体的模块化分离感
是设定的一部分。

被注视时（或按 `B`/`N`）爆散：模块按错峰、各自独立的二次贝塞尔弧线飞向
新位置，中途云团半径约 1.4–2.8m（默认 1.84m），明显散开而不是整体平移；
随后收敛重组，5.6mm 级误差归位。默认瞬移 5m（参数范围 0–12m）。

`idle`：双手背在身后、微微起伏；`walk`：低速滑行 + 缓慢迈腿，脚始终离地；
`attack`：从背后抬手 → 手臂平举指向玩家 → 掌心充能 → 发射旋转能量手里剑 →
后坐 → 收手回背后。手里剑在 clip 结束后仍按 1.05s 生命继续飞行并自清。

### 绑定 / 参数

45 个关节、42 个参数；模块按关节分配，装配态姿势完全由关节驱动；JOINTS 页
可单独摆姿势。`module_size` / `module_gap` / `thruster_intensity` / 爆散
半径/错峰/飞行时间/重组时间/过冲/瞬移距离/手里剑速度自旋尺寸等全部接线。

### 实测

| 项 | 数值 |
| --- | --- |
| 身高 / 悬浮（脚底-台面） | 1.60 m / idle 0.207m、walk 0.209m、attack 0.209m |
| 模块 | 默认 90（参数 60–90），每模块独立推进器；`module_size` 名义 0.10m、默认实测平均最大边 0.109m |
| 爆散 | 位移 6.03m 测试、云团半径 0.84→2.66m（中段 1.84m）、98.1% 模块对间距改变 |
| 重组误差 | 5.6 mm |
| 性能 | 117.5–117.9 fps 无 vsync（SSR 开启）/ 60 fps vsync，351 draw calls，42.9k prims |

---

## LEVIATHAN // ABYSSAL WARDEN

机械章鱼最终 Boss：2 m 半径装甲球（直径 4 m）+ 8 条独立链式触手。每条触手由
**0.30 m 连杆 + 0.31 m 球形关节**交替组成（0.60 m 一个周期），细、等粗、无吸盘；
球形关节是可见的旋转节点。idle 长度 **15 m**；关节图案以末端为基准，长度变化时
新链节从球内孔洞伸出/缩回，球外没有任何被压缩的超长节。球心默认在 **6.0 m**，
触点从 52° 下倾的孔洞沿轴线伸出 0.88 m 后再弯曲，不会从孔上方穿模。

- 角色规则：同时至多 2 条 attack、至多 5 条 support；**存活 ≥3 时至少保持 3 条
  support**（被砍掉会立刻由 idle 补位）。存活 **<3** 时球体落到地面（2.22 m），
  所有剩余触手持续攻击；不再有“少于 3 条不能砍”的限制。
- 眼睛：球壳内的红色大摄像头镜头，万向节自由跟踪；一阶段只从 36.3° 孔径露出，
  二阶段 8 片虹膜滑入后壳、孔径 100°、红色能量球点亮、外壁透明、可发射激光。
- 攻击：attack1 先把末端对准目标再加速直刺、穿过目标后减速（预瞄准 dot 0.990+）；
  attack2 先到目标上方 5.5 m、垂直向下加速穿过胸口；attack3 把 **20 m** 触手的
  整段远端放低到 **1.0 m**，绕身体 **360°** 横扫，与其他腿完全独立。
- 切割：从尖端开始逐节爆炸（火花/碎片/短暂闪光/白热断口），一路烧到根部后消失；
  爆炸池全部会自行过期，不会在旧根部留下持久特效。
- 验收：`cd main/content/enemies/boss/leviathan && godot --headless --path . res://scenes/qa.tscn` →
  **61/61 PASS**，0 failures；idle 互穿间隙 +0.706 m，support +1.051 m，
  attack3 357.8°/21.4 m/1.0 m，support 补位与坠落攻击、cut 顺序/无残留均通过，
  模拟 8.2 ms/60 Hz step。
- 视觉验收：直接运行主程序（`cd main/content/enemies/boss/leviathan && ./run.sh`）用右侧面板操作；本构建
  不再生成/附带成堆的验收图片。

```bash
cd main/content/enemies/boss/leviathan
godot --headless --path . --import
godot --headless --path . res://scenes/qa.tscn
```

## 验收结论

**独立只读审计**（复制到 `/tmp` 重跑，不采信实现者自述）覆盖：
契约 API、动画名称/时长、确定性 scrub、循环接缝、全部关节有效性、参数
极值重建、无外部资源、性能、UI 功能与截图。审计发现的问题已按优先级修复，
并做了二次复测：

- Sentinel v3：全量重做（三角履带炮塔 + 单臂 + 可旋转内球光学 + 状态灯）；
  5 个 clip 逐帧自碰撞为正，全部可达转场为正；attack1 正上方重砍 / attack2 横扫
  姿态与 479° 扫掠角通过；8 个威胁方向 block 命中误差 0.0000 m、刀面 0.0°、
  净空 ≥0.043 m、首次规划 11–20 ms；光球追踪 0.00°、外壳逐姿势零变换；
  履带-车轮物理耦合（ω·r = 线速度）/ 左右差速 / 3 m/s 上限 / 与 body clip 解耦；
  身高 1.558 m、光学半径 = 边长/3；
  旧版双轮、盾、刀鞘、guard 兜底与烘焙轨迹表全部移除。
- Shard：`module_size`/`module_gap`/`thruster_intensity` 死参数 → 实测生效；
  掌心永久橙色方块 → 球形充能、非攻击隐藏；笑脸面罩 → 单个大型相机镜头；
  肩/手穿插 → 手间距 0.08m；50 模块覆盖不足 → 下限 60 并自动放大模块；
  loop 接缝 8mm → 0.000m；手里剑 clip 后冻结 → 继续飞行并自清。

**LEVIATHAN** 的验收数字与已知限制见 `boss/README.md`、`boss/DESIGN.md`、
`boss/renders/qa_report.json`；视觉验收直接运行主程序。

**定位**：按独立游戏/中型项目可用的风格化角色标准交付；工程结构、确定性、
参数化、性能与动作可读性达标。视觉上是硬表面 + 程序化微表面（划痕/色差/
边缘磨损/SSR）的风格化建模，仍不是 3A 影视级资产——与商业 3A 的主要差距
在：整体造型的细节密度、拓扑级倒角/磨损、以及手 K 级别的动画打磨。所有
已知限制都写在各工程 README（`arc_sentinel/README.md`、`shard_phantom/README.md`）中，不隐藏。

---

## 已知限制（诚实清单）

**ARC // SENTINEL v3**
- 身高 1.56 m 量到肩部球关节顶（不含机械臂）；手臂全举时整体约 2.8 m。
- 炮塔相对底盘只能偏转 ±8°（立方体夹在两履带之间）；更大的转向由左右履带
  差速完成（独立驱动层，`set_track_speed(L, R)`）。
- 光学窗口做到边长 1/3 后，红色球冠会突出正面约 6 cm，无法同时满足「突出很小」。
- 攻击动作有重量感（1.07–1.16 s），不是极速快挥。
- block 首次规划 11–20 ms；按需调用，不逐帧规划；同一方向缓存后 0 ms。
- 金属细节是程序化风格化硬表面，不是扫描级 3A 贴图。
- 进程退出时 Godot 报少量生成纹理 RID 泄漏；运行中无影响。

**SHARD // PHANTOM**
- 肩/上臂模块簇在 3/4 视角仍偏拥挤；这是下一次美术迭代的首要项。
- 模块数下限为 60（原需求 50–90），低于 75 时自动放大模块以维持覆盖；50 个时仍会明显变稀。
- 正面攻击图因朝相机投掷而透视缩短，侧视 `attack_side.png` 才是手里剑的判读图。
- 爆散/重组的时间轴拖动需要触发时的快照；重建几何会把飞行中的蜂群重置为装配态。
- 舞台刻意接近全黑，角色的可读性依赖高光边与自发光；这是风格选择，不是曝光错误。
- SSR + 金属 shader 使无 vsync 帧率从 ~119 降到 ~83–85；60fps 输出仍有余量。

---

## 目录

```text
boss/
  scenes/studio.tscn          交互演示主场景（8 条触手、角色调度、两阶段、激光）
  scenes/qa.tscn              全量验收（61 项）
  scripts/boss/               骨架、虹膜壳、万向节眼、能量核心、链式触手求解器
  scripts/qa.gd               无头验收
  shaders/                    金属、镜头、壳玻璃、等离子球/核心、激光、地面、3D 火焰/烟雾
  renders/qa_report.json      61/61 PASS
  README.md / DESIGN.md

arc_sentinel/
  scenes/studio.tscn          交互演示主场景
  scenes/character.tscn       角色（契约接口）
  scenes/qa.tscn              全量验收 QA（碰撞/转场/姿态/规划/光学/履带/灯）
  scenes/v3_shots.tscn        动作分解帧（960×540，16 帧 ×4 视角 ×5 clip）
  scenes/v3_details.tscn      全身图 + 光球/履带/关节/刀柄特写
  scenes/perf_v3.tscn         帧率/绘制统计探针
  scripts/ch/                 骨架/几何、解析 IK、动画/规划、材质、电弧刀
  scripts/kit/                共享网格/材质/面板/演播室
  shaders/                    金属、光球、镜片玻璃、电弧、拖尾、地面、调色
  renders/v3/                 最终图、特写、分解帧、QA 报告
  README.md / DESIGN.md

shard_phantom/
  scenes/studio.tscn          交互演示主场景（含 BLINK/GAZE 控件）
  scenes/character.tscn       角色（契约接口 + 爆散状态机）
  scenes/perf.tscn            性能探针
  scripts/phantom/            模块场、绑定、手里剑、材质
  renders/                    最终图、blink 条带、特写、ACCEPTANCE.md
  README.md
```

### 生成与验收命令

```bash
# Sentinel v3
cd main/content/enemies/melee/arc_sentinel
godot --headless --path . res://scenes/qa.tscn
DISPLAY=:10 godot --path . res://scenes/v3_shots.tscn
DISPLAY=:10 godot --path . res://scenes/v3_details.tscn

# Shard
cd main/content/enemies/phase/shard_phantom
DISPLAY=:10 godot --path . res://scenes/perf.tscn
godot --headless --path . --script res://scripts/contract_test.gd
godot --headless --path . --script res://scripts/loop_soak_test.gd
DISPLAY=:10 godot --path . res://scenes/shots.tscn
```

---

## 实现与调度记录

- `arc_sentinel` v3 为**全量重做**：新骨架（双三角履带 + 立方体炮塔 + 单臂）、
  几何、材质、解析 IK、四元数轨迹、运行时 block 规划、QA 与视觉验收全部在
  `arc_sentinel/` 内，详细记录见 `arc_sentinel/README.md` 与 `arc_sentinel/DESIGN.md`。
- 本次按用户反馈调整比例：身高 1.56 m（不含臂）、履带改为钝角三角形并重做金属
  履带板细节、立方体缩小而光学窗口放大到边长 1/3、剑柄改全黑、眼下加 6 颗
  绿/橙/蓝闪烁状态灯。
- v3 的几何、绑定、动作、规划、验收与渲染均在本会话内完成；沿用 v2 已移植的
  电弧剑场与程序化金属 shader。
- 视觉验收：`renders/v3/` 下为最终图、特写与逐帧动作分解；旧 `renders/v2/` 已清理，
  旧 v2 的烘焙轨迹表、盾、刀鞘代码全部删除。