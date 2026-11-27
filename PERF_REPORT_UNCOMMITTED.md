# TURN「坠击中庭」(level 5) 性能优化报告 —— 未完成项存档

**状态**：此文件本地保留、未提交。优化主体已提交，剩余思路记录在下方「未完成项」。
**日期**：2026-11-26 · 测试机：GTX 1650 · DISPLAY=:10 (xrdp 1920×1080) · Godot 4.7.2 Forward+

## 结论速览

| 阶段 | p50 帧时 | GPU 帧时 | 备注 |
|---|---|---|---|
| 优化前基线（真模拟，6 敌全活） | 54 ms（~19 fps） | ~13 ms | p95 93ms / max 132ms |
| 本轮优化后 | ~18 ms（~55 fps） | 15 ms | gap 12ms + 6ms 游戏逻辑 |
| 用户实测 | ~40 fps | — | 受同机 sunshine 串流游戏争 GPU 影响，数值偏低 |

瓶颈自始至终在 **CPU 侧**（GPU 只有 13ms），不是模型/画质。

## 已落地的修复（已提交）

1. **sentinel 寻路每帧重算是最大热点**（`level.step` 42ms/帧，其中 `arc.ai`→`nav.*` ~36ms）
   - `position_clear`：原来对 142 个 AABB 全量扫描 + `walkables.has()` 线性查找（O(solids×walkables)）→ 改为一次性 `_solid_boxes`/`_solid_walk` 缓存 + **2m XZ 空间网格**（`_solid_grid`/`_solid_seen`），只查附近的盒子。语义不变。
   - `duelist_floor`/`floor_at`/`melee_clear` 同样改为遍历预缓存数组。
   - `_sentinel_ground_waypoint`：10Hz / 位移 0.6m 复用寻路点（`_wp_*` 缓存）。视野与判定无差别。
   - 效果：`level.step` 42ms → 3ms/帧。

2. **怪物模型碎片化网格合并**（不降画质）
   - `mesh_kit.merge_child_meshes`：同一动画枢轴下、同材质的单表面 MeshInstance3D 合并为一个网格；顶点烘到父节点局部空间；跳过 top_level/骨架/多表面/不同可见性的件。
   - `merge_subtree_meshes`：把整个静态子树（如轮子内部、排除可击飞装甲板 `_drive_plates`）合并到枢轴。
   - arc sentinel：151 → 142 mesh；wheel sentry：723 → 278；Vesper：合并曾试过（300→186），**已撤回**（见未完成项 #4）。

3. **修复上游回归**：`session.gd` 恢复 `get_option`/`display.vsync`（9723e8d revert 误删导致 galleria 环境没挂上）。
4. **F5 调试 HUD**：每帧刷新的帧时/FPS/60帧均/p95/max/GPU ms/CPU/物理/draws/prims/敌人数；`-- --no-mouse-capture` 下不抢菜单的 F5。
5. **`--play-bench`** 真模拟基准（`tools/play_bench.gd` + `menu.gd` 挂载）：真实输入驱动玩家、无传送、`--ablate=` 消融、`--inspect` 网格分布诊断、`--idle` 静置、`--screenshot/--report`。
6. **撤回的中间方案（会踩的坑）**：
   - 用 `P.perf_*` 探针打在共享 `arc_encounter.gd` → 只有 galleria 的 `PService` 有 `perf_enabled`，其他关每帧 `step` 报错 → sentinel 原地挂机。**所有探针已全部移除**。
   - `merge_child_meshes_filtered` 用在玩家机甲 → 玩家身体外壳消失 → **已撤回**，玩家模型不做合并。

## 未完成项（下一步候选，按性价比排序）

1. **GPU 仍 ~15ms**（空场景 gap≈3ms）：`--ablate=arena` 隐藏整个中庭场景后 GPU 掉到 3ms，而隐藏全部敌人仍是 15ms → 瓶颈在**场景自身的着色器/填充率**，不是怪物网格。候选：检查 art.gd 的 `plate/wall/metal/glazing` 手写 shader 成本、`STATIC_REFLECTION_LAYER` 件数、shadow pass。
2. **present/提交端 ~12ms（gap）**：`post_process_gap_p50 ≈ 12ms`，即使 GPU 6ms 也不变 → 像是 canvas/HUD 提交 + present 节流。`--ablate=hud` 无变化；可能受 `content_scale` 影响（见 #3）。
3. **渲染目标超采 2.04×**：`texture_size=2286×1471`，但 `viewport_size=1920×1029`、`content_scale=1120×720`、`scaling_3d_scale=1.0`。实际 3D 渲染分辨率是设计分辨率的 ~2 倍 → 查 `stretch/mode=canvas_items` + `window/size/mode=3`（maximized）在 xrdp 下的换算；若确为 bug，修正即可大幅降 GPU 且**不降画质**（本来就是超采）。
4. **玩家机甲合并**：撤回的原因是「第三人称下外壳消失」。重新启用前先弄清 `set_body_hidden`/`body_builder` 里按节点名/可见性开关的件（torso 直属子节点、Shoulder* 除外规则），把它们加进 skip 白名单后再合。
5. **VoxelGI 质量**：`SUBDIV_128` + `use_two_bounces=true` 每帧 ~6ms；`global_illumination/voxel_gi/quality=0` 在该机几乎无变化（烘焙已缓存到 `user://neon_geometry_gi.res`）。如要再省，考虑 SUBDIV_64 或把 `use_two_bounces` 关掉对比画质。
6. **重复测量避免同机干扰**：实测时确认没有别的 Godot/sunshine 实例占 GPU（`nvidia-smi`），否则数值会被显著拉高（出现过 42ms GPU 的污染样本）。

## 复测命令

```bash
# 真模拟基准（真实输入、无传送、6 敌全活）
python3 main/tools/prepare_game.py
DISPLAY=:10 godot --path main -- \
  --play-bench --level=5 --warmup=2 --measure=8 \
  --screenshot=/tmp/opencode/shot.png --report=/tmp/opencode/report.json \
  -- --no-mouse-capture

# 消融
--ablate=enemies|arena|lights|gi|probe|shadows|post|msaa|hud|particles|player|all   # 可逗号组合
--inspect   # 打印每种敌人按父节点的网格分布
--idle      # 静置（不驱动玩家）测纯场景开销
```
