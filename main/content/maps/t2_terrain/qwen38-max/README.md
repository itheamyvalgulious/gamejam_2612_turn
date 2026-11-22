# 任务 2 · 自然地形（10 km²）— qwen-3.8-max

Godot 4.7.2 纯程序化自然地形：**雪原 / 热带雨林 / 山地悬崖河谷** 三生物群系，
世界尺寸 4000 m × 2500 m = **10 km²**。零外部美术资产：几何体拼接 + 参数化曲面 +
数式纹理（GLSL 噪声）+ 自写 shader 全部代码生成。

## 运行

```bash
# 交互浏览（WASD+QE 移动，按住右键拖拽转向，Shift 加速）
DISPLAY=:0 godot --path . res://scenes/main.tscn

# 批量出图（6 个机位，2560×1440，离屏 SubViewport）
DISPLAY=:0 godot --path . res://scenes/main.tscn -- --capture
```

截图输出到 `screenshots/`：
`01_overview`（三群系全景）、`02_jungle_river`、`03_mountain_gorge`、
`04_snowfield`、`05_jungle_ground`（雨林河道地面视角）、`06_gorge_river`（峡谷崖壁）、
`07_snow_close`（雪原贴近地面：雪堆/灌木/覆雪针叶/风蚀雪面）。

## 架构（全程序化）

| 文件 | 作用 |
| --- | --- |
| `scripts/terrain_gen.gd` | 高度场/生物群系生成：域扭曲 fBm 大陆基底、雪原高原、雨林低地、东西向 ridged 山脉 + 冰川谷、阶地崖壁（高度量化）、解析式河谷雕刻（平原 U 形 / 山区 V 形峡谷）、纬度+海拔气候模型、4 通道 splat（草/岩/雪/沙）、坡度二次修正 |
| `scripts/terrain_lod.gd` | 分块 LOD 网格：250 m 块 ×4 级分辨率（5/10/25/50 m 步长），按相机距离切换，向下裙边隐藏 T 型接缝 |
| `shaders/terrain.gdshader` | 数式纹理：3D value-noise fBm/ridged，四材质 splat 混合；**岩壁：变倾角层理（dip 随空间旋转）、双频层系、岩性大斑、垂直渗水暗痕、崖脚碎石坡积物、陡壁强制裸岩**；**雪面：定向 sastrugi 风蚀沟槽（含背风雪檐唇，进 bump）、雪层色调（新雪/壳/蓝粒雪）、露出岩脊**；苔藓、雪线盖顶、沙纹；程序化 bump 法线（噪声有限差分）+ 距离衰减 |
| `scripts/water.gd` + `shaders/water.gdshader` | 南端湖平面 + 沿河谷下坡的河流条带；shader 做 gerstner 式波法线、屏幕深度浅/深变色、岸边泡沫、Fresnel 高光 |
| `scripts/vegetation.gd` + `shaders/foliage.gdshader` | 程序化植物：阔叶树（干+枝+噪声孔洞 alpha 树冠球）、**3 套针叶树变体（层数/冠幅/偏斜不同）+ 随机旋转/非等比缩放/倾斜 + 噪声聚簇疏密**、灌木、草（交叉四边形+叶片 alpha）、岩石（噪声变形球）、**雪堆与覆雪灌木**；树冠 shader 支持顶面积雪染色；按 splat/坡度/湿度/焦距 MultiMesh 实例化散射 |
| `scripts/main.gd` | 环境（ProceduralSky + 太阳 + 高度雾/体积雾 + Filmic）、**程序云层（fBm 覆盖率高空平面 shader）**、相机、多机位离屏截图（支持 snap 贴地机位） |
| `tools/preview_gen.gd` | 无头导出高度图/生物群系顶视预览（`_preview_*.png`） |

## 关键参数

- 高度场：5 m 网格，801×501 顶点；海拔 1–487 m。
- 群系布局（沿 Z 轴气候梯度）：北=雪原高原，中=山脉+贯穿河谷，南=雨林低地+湖。
- 植被实例上限：阔叶 16k / 针叶 4k / 岩石 3k / 灌木 6k / 草 40k（焦距衰减）。

## 复现截图

`DISPLAY=:0 godot --path . res://scenes/main.tscn -- --capture`（GTX 1650，Vulkan Forward+）。
可附机位关键字只出部分图：`-- --capture 04 07 03`。

## 第三轮定点强化（近距写实）

- 针叶树冠：锥面按 3D 噪声做径向/竖向顶点置换（枝簇起伏），每层随机方位「缺枝扇区」，整树非对称偏斜；叶面 alpha 噪声挖空使外轮廓碎裂；背光叶透光（暖色 SSS 项）+ 底面暖色地光反弹，消除阴影面发闷蓝。
- 岩石：实例下沉约半个身位埋入地表，变形幅度加大出棱角，分布放宽到碎石坡带（slope 0.35–0.85）成坡积群。
- 雪面：雪粒尺度高频 albedo/roughness/bump 细节；明暗交界加次表面暖光过渡（view·sun 背散射项），阴影蓝色淡化，不再生硬蓝白带。

## 第四轮（1–3 m 特写达标 / 立体树 / 流动水）

- **精度根因修复**：旧 `hash13` 的 fract-dot 哈希在大世界坐标×高倍频下浮点精度崩溃、退化为轴向条纹；改为精确整数位混合哈希，所有程序噪声恢复各向同性。
- **尺度不变细节**：bump 改梯度噪声（Perlin 型、C1 连续无格纹）分形，八度上限随像素足迹 e=clamp(dist·0.0012, 0.02, 0.6) 自适应 → 1 m 特写清晰、不糊不_alias；albedo 叠亚米级 grain；视差项经评估移除（折叠伪影）。
- **立体树**：近景树为递归枝干骨架（渐细圆柱 3 级分枝）+ 枝端叶片丛卡片（程序化复叶/针叶 alpha：中脉、锯齿缘、双族针叶条）+ 实心核心锥保证体量；顶点色烘焙簇内 AO；背光透光 + 地光反弹；远景用低模 impostor（近/远双 MultiMesh，近景针叶 ≤2000、阔叶 ≤2600）。
- **流动水**：河道条带沿程 UV（UV.x=沿流米数）+ 横向 7 细分；shader 沿切向平流噪声、顶点几何波浪（急流振幅加大）；急流白沫条纹、岸边涟漪泡沫、屏幕深度岸沫；两级跌水台阶（14 m / 10 m）+ 跌水底溅射水雾（半透明球壳）；急流段礁石露出。
- **性能**：LOD 块重建预算 2 块/帧，交互平移不卡顿。
- **新增特写机位**：08_rock_close（1–2 m 岩面）、09_snow_micro（1 m 雪面）、10_tree_close（单株针叶）、11_river_close（水面流纹）、12_waterfall（跌水+水雾）。
