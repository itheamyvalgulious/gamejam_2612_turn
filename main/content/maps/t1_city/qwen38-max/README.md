# NEO-VERTEX — 纯程序化赛博朋克巨城（10.5 km²）

Godot 4.7.2 / Forward+ / 全程序化：无外部模型、无贴图资源。所有几何由 GDScript 按种子
生成（几何体拼接 + 参数化曲面），所有材质纹理由着色器数学公式实时计算。

## 运行

```bash
# 交互漫游（点击捕获鼠标，WASD+QE 移动，Shift 加速，滚轮调速，Esc 释放/退出）
DISPLAY=:0 godot --path .

# 自动截图（10 个机位，输出到 shots/）
DISPLAY=:0 godot --path . res://scenes/shots.tscn -- --seed=1337

# 参数
--seed=N        城市随机种子
--focus=x,z     细节中心（细节分级围绕该点）
--only=a01,...  只渲染指定机位
--day / --nofog / --noglow / --nomsaa  调试开关
```

生成耗时约 2~3 秒（单线程 GDScript），4100+ 栋建筑、约 70 万三角面（chunk 合并网格）
+ MultiMesh 实例（路灯/车辆/行人/树/信号约 1~2 万实例）。GTX 1650 @1080p 可实时漫游。

## 规模与坐标

- 城区 3500 m × 3000 m = 10.5 km²，单位 = 米（真实尺度：层高 3.1~4.4 m、车道 3.2 m、
  人行道 2.5~4 m、干道红线 26 m、本地路 15.5 m）。
- 路网：125 m 正交格网 + 单纯形噪声位移（节点 ±16 m）+ 路段中线弯曲噪声；
  每 4 条线升格为干道；交叉口用 8 点凸包补面。
- 街区：单元格四边按路宽+人行道内缩（半平面求交），再递归二分地块（目标面积按功能区）。

## 功能区（Voronoi）

20 个种子点： downtown×2 / commercial×3 / res_high×3 / res_low×4 / school×2 /
industrial×3 / park×2 / civic×1。每区控制：高度包络、风格权重、地块面积、
霓虹密度、绿化密度（`scripts/districts.gd`）。

## 建筑（`scripts/building_gen.gd`）

- 足迹形状：矩形 / 切角 / L 形 / U 形内院；塔楼 = 裙房 + 1~3 级退台（tier 列表）。
- 风格 8 种：玻璃幕墙、公司石材、公寓（阳台板+栏杆几何）、砖砌、工业厂房（壁柱）、
  学校、 mega、奢华暗玻；风格编码进 COLOR.a（style*16+首层高）/255。
- 屋顶：女儿墙、机房、水箱、空调组、天线+航空障碍灯、直升机坪、光伏板。
- 霓虹：角部竖向灯带、屋顶灯线（顶点色自发光）。
- 细节分级（以 focus 为心）：R_DETAIL=520 m 完整家具级；R_MID=1050 m 完整外形；
  之外仅体量（着色器承担全部立面细节）。
- 玻璃楼（focus 620 m 内）走半透明幕墙 + **真实室内**（`interiors_gen.gd`）：
  楼板、发光天花灯带、核心筒、隔墙、桌/沙发/显示器（自发光屏幕）。

## 参数化曲面 / 数学建模

- 扭转塔：46 层方形截面随高度旋转 60°、线性收分（`landmarks_gen._twist_tower`）。
- 尖塔：八边形截面 r(h) 幂函数收分 + 70 m 桅杆。
- 穹顶体育馆：球冠参数面 (θ, φ) 网格。
- 双曲冷却塔：r(y) = r_min·cosh((y−y_c)/a) 旋转面。
- 摩天轮：圆环参数布置轮缘/辐条/座舱。
- 拱形车站雨棚：半圆柱参数壳；天际铁路桥墩/箱梁沿 Catmull-Rom 样条。
- 河流：中心线 z(x) = lerp + A·sin(kx) + noise；宽度噪声调制；
  桥梁在道路跨河处自动生成（干道→斜拉桥：H 形塔+扇面索；本地路→梁桥）。
- 高架高速：两条走廊（y=12 / y=19 m）+ 苜蓿叶式联络匝道（参数螺旋）+ 桥墩/防撞墙/底面灯带。
- 电缆/灯杆/行道树/车辆/行人/飞行器：MultiMesh 实例化沿路网样条布点。

## 着色器（纯公式纹理，`shaders/`）

| 文件 | 内容 |
|---|---|
| facade.gdshader | 8 风格立面：窗格 hash 布局、亮窗+家具剪影、砖/肋金属/污渍/水痕、首层商铺+程序化汉字笔画霓虹招牌带（线段距离场）、距离自适应细节淡出 |
| glass.gdshader | 幕墙：mullion 网格、逐层办公灯带、Fresnel 反射、半透明见室内 |
| interior.gdshader | 室内双面材质，UV2.x=自发光掩码 |
| road.gdshader | 沥青 FBM、修补块、车辙磨损标线（中线双黄/边线/虚线按 UV 米坐标）、水洼镜面 |
| paint.gdshader | 标线漆磨损 alpha |
| neon_sign.gdshader | 霓虹灯牌：边框灯管 + 笔画字形 + 闪烁/坏灯 |
| holo.gdshader | 全息广告：流场渐变、圆环、扫描线、故障条 |
| water.gdshader | 三向正弦波解析法线、Fresnel 天光、城市霓虹倒影光柱 |
| prop_vc.gdshader | 顶点色道具：COLOR.a=自发光掩码（灯头/车灯/屏幕） |
| pool.gdshader | 路灯地面光池（加性径向衰减） |
| plain/grass/emissive_vc | 通用噪波面 / 草地 / 顶点色自发光 |

所有着色器内置**距离霾**（`1−exp(−d·k)` 向地平线色混合）替代 Environment fog
（Godot 4.7 该雾在离屏视口下存在整屏黑 bug）。

## 已知引擎坑（4.7.2，本项目已绕过）

1. `ArrayMesh` 属性数组类型：UV/UV2 必须 `PackedVector2Array`、COLOR 必须
   `PackedColorArray`、VERTEX/NORMAL 必须 `PackedVector3Array`，否则 surface 静默创建失败。
2. 三角形绕向：本项目 `MeshBuf.quad_o/tri_o` 以几何法线点积校正（4.7 的剔除面判定与
   常规假设相反，曾导致全部外表面被背面剔除）。
3. hash 输入禁止叠加连续插值的大数种子（浮点插值误差被 hash 放大为逐像素盐噪）；
   种子先 `floor(x+0.5)` 量化再入 hash。
4. `Environment.fog_*` 在 SubViewport/主视口离屏渲染下整屏黑 → 用着色器距离霾替代。
5. `DirectionalLight.energy=1.0` 即白昼量级；夜景月光需 ~0.05。

## 截图（shots/）

a01 高空全景 / a02 市中心斜视 / a03 街道峡谷 / a04 城市边缘 / a05 河流与桥 /
a06 高架走廊 / a07 玻璃幕墙室内（桌椅/显示器/灯带/核心筒） / a08 港口+摩天轮+冷却塔 /
a09 正射俯瞰 / a10 学校与居住区 / a11 近景立面材质 / a12 滨水步道

## 本轮迭代（v2）

### 室内精细按需生成（interiors_gen.gd + interior_streamer.gd）
- 完整楼层平面：核心筒（2~6 部电梯井+门洞发光）、双楼梯（全细节层带踏步）、
  卫生间（隔间+洁具）、管井；走廊墙带门洞；房间隔墙按 4~7 m 开间递归划分。
- 陈设随类型/楼层变化：办公（桌+发光显示器+椅+书架+桌灯）、公寓（床/沙发/厨柜/餐桌）、
  开放办公区、设备层（管道+罐体）、大堂（接待台+发光背墙+沙发+绿植+导光带）、
  每层 3 条天花灯带（顶层不装，避免穿帮）。随机种子 = 建筑种子×层号，逐层不同。
- 按需流式：InteriorStreamer 以相机为中心按 chunk（500 m）懒生成，单帧预算 10 ms，
  0.35 s 检查一次，>1.6 km 驱逐；截图模式 force_at() 同步预建。全城内景约 110 万三角面（仅按需实例化）。
- 细节分级：R_FULL=240 m 全平面+家具；R_MED=650 m 板+核心筒+柱；其余仅着色器假内景。

### 着色器质感（v3）
- facade：材质分层（金属框/介电玻璃/spandrel/风格墙各自 metal-rough）、窗洞 recess AO +
  檐口压暗、视差内景（VIEW 位移家具/天花剪影）、百叶/家具/径向光衰、窗帘/空调机/绿植/
  开窗暗洞四种窗型、雨痕/裂缝/海报/涂鸦、切线空间凹凸法线（panel/砖缝/肋/裂缝高度场）、
  亮窗 halo + 窗台溢光 + 首层招牌/橱窗溢光落到墙面、距离 sparkle 平均项。
- glass：mullion 倒角、污渍条纹、视向霓虹反射柱、掠射蓝绿厚度色、逐层灯带灯具行。
- road：骨料/裂缝网络（含凹凸）/修补块/轮迹/井盖/水洼镜面+霓虹倒影+月光 glint/标线磨损。
- water：4 向解析波、岸线泡沫、月光 glint 路径、涟漪扭曲霓虹倒影柱。
- sidewalk：铺装板+缝+口香糖+垃圾+墙根积垢+橱窗溢光带+湿斑。
- neon_sign：锈背板+灯管 core/halo+死段+玻璃罩光泽。
- plaza（新）：放射环缝+发光镶嵌环+湿斑，用于地标广场。

### 地标成景（landmarks_gen.plan/build_nodes）
- 扭转塔 → 圆形广场：放射步道接四条路、树环/长椅/bollard 灯、入口雨棚；周边 cell 覆盖为 plaza。
- 冷却塔 → 工业场院：管廊架接西侧厂房、围栏、警示灯；cell 覆盖为 yard。
- 摩天轮 → 滨水步道：木栈桥、摊位（ awning+暖光前脸）、悬链串灯；轮缘双侧灯环+轮毂光。
- 天际铁路车站 → 站前广场：人行横道、公交候车亭（发光广告面）、街道电梯塔、bollard 灯。
- 斜拉桥 → 桥头条：两岸观景平台（栏杆+灯带+长椅）。

## 代码结构

```
scripts/
  city_gen.gd      编排：环境/路网/街区/功能区/chunk 合并输出
  city_math.gd     凸包、半平面内缩、地块递归二分、Catmull-Rom
  districts.gd     Voronoi 功能区与类型参数
  building_gen.gd  建筑装配（足迹/退台/风格家具/屋顶/霓虹）
  interiors_gen.gd 楼层平面/陈设生成器（v2）
  interior_streamer.gd 相机中心 chunk 流式加载（10ms 帧预算）
  props_gen.gd     路灯/光池/车辆/飞行器/树/行人/信号/招牌/全息牌
  infra_gen.gd     河流/桥/高架/匝道/天际铁路/车站/港口吊机
  landmarks_gen.gd 参数化地标
  mesh_buf.gd      快速网格累加器（float 流 → ArrayMesh）
  shots.gd         离屏 SubViewport 自动截图
  free_cam.gd      漫游相机
```
