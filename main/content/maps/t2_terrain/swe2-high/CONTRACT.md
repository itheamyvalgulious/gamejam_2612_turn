# T2 Terrain — module contract (frozen)

Project root: 本目录（仓库内相对路径 `mapbuilder/t2_terrain/swe2-high/`）
Godot 4.7.2, Forward+. Run: `DISPLAY=:0 godot --path .`

## HeightField API (src/height.gd — stable, do not edit)

```gdscript
class_name HeightField
extends RefCounted

const X0 := -2048.0; const X1 := 2048.0   # world bounds x
const Z0 := -1280.0; const Z1 := 1280.0   # world bounds z

var river_pts: PackedVector2Array          # smoothed spline, XZ points
var lake: Dictionary  # {"c": Vector2(500,980), "r": 320.0, "y": 2.0}

func h(x: float, z: float) -> float        # terrain height (metres)
func slope(x: float, z: float, e := 4.0) -> float   # gradient magnitude
func splat(x, z, y, slope) -> Color        # (snow, rock, jungle, sand) weights
func river_dist(p: Vector2) -> Vector2     # -> (dist_to_spline_m, arc_t 0..1)
func river_water_y(t: float) -> float      # water surface Y at arc t
func water_y(x, z) -> float                # water surface Y at point
```

Biomes: snow plateau `z < -400` (y≈105-140); mountain band `z -350..350`
(crest ~z 60, peaks ~400 m, gorge along river); jungle basin `z > 400`,
lake centre (500, 980) r=320 y=2. River: source → gorge → waterfall lip
(t≈0.555, y 40) → plunge pool (t≈0.585, y 12) → delta → lake.

## Ownership

- `src/main.gd`, `src/terrain.gd`, `src/height.gd`, `gfx/terrain.gdshader`,
  `gfx/common.gdshaderinc`, sky/env — **main agent (t3-swe)**
- `src/water.gd` + `gfx/river.gdshader` + `gfx/lake.gdshader`
  + `gfx/falls.gdshader` — **worker t2-water**
- `src/veg.gd` + `gfx/leaf.gdshader` + `gfx/rock.gdshader` (+optional
  `gfx/spore.gdshader`) — **worker t2-veg**

## Integration contract for workers

Provide a `class_name` on a `Node3D`-extended script:

- `src/water.gd` → `class_name RiverWater extends Node3D`
- `src/veg.gd`  → `class_name Vegetation extends Node3D`

Constructor/build API (called once after `_ready` adds you as child):

```gdscript
func build(hf: HeightField) -> void
func update(dt: float, cam_pos: Vector3) -> void   # per-frame, may be a no-op
```

Rules:
- Pure procedural: ArrayMesh / ImmediateMesh / MultiMeshInstance3D /
  Particles — no external textures or assets. Shaders you write yourself.
- Trees must be true 3D (frustum trunk + lobed canopy / conifer tiers);
  no billboard cards. Wind sway may be vertex shader on leaf material.
- Water: river follows `river_pts` with real downhill flow direction,
  3-D wave displacement in the VERTEX stage (sum of gerstner/sine), foam
  streaks near banks, animated waterfall sheet + plunge foam ring + spray.
  Lake: gentle broad swells + shore ring foam.
- LOD/perf: budget < ~1.5 M tris total, prefer MultiMesh for veg; skip
  instances farther than ~900 m unless inside a close shot region.
- Do NOT edit files you don't own. Do NOT run `--shot` (main renders).
  You may run `godot --path . --check-only --script <your file>` to
  syntax-check (height.gd compiles cleanly now — use it as style ref).
- Godot 4.7 GDScript gotchas: no `mix()` (use `lerpf`/`lerp`), explicit
  types needed when inferring from Variant/Array elements, no `print`
  spam in `_process`.
