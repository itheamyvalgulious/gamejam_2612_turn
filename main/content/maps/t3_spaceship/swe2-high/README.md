# ISV MERIDIAN — procedural starship walkthrough (Godot 4.7.2)

A 300 m exploration ship built **100 % from code**: no bitmaps, no external
assets, no imported meshes. Every surface is batched procedural geometry;
every material is a custom `ShaderMaterial` driven by math (value-noise fbm,
panel fields, brushing, rivets, emissive masks). UVs are metric (1 texel ≈
1 m), vertex `COLOR` carries per-part seed / height / kind / wear so a single
material produces thousands of visibly different parts.

## Run

```bash
cd t3_spaceship/swe2-high
godot --path .
```

Flycam: WASD + mouse (click to capture, ESC releases). Keys:

| Key | Action |
|-----|--------|
| 1–9 | Teleport along the route: engine → reactor → fuel → machine → cargo → atrium → habitat → command → bridge |
| V   | Toggle hull visibility (interior is hidden automatically when inside) |

## Still shots

```bash
godot --path . -- --shot=<name[,name2,...]>
godot --path . -- --shot=all
```

Writes `shots/<name>.png` (1920×1080) and exits. Presets: `ext_hero`,
`ext_bow`, `ext_stern`, `ext_side`, `ext_top`, `ext_detail`, `in_engine`,
`in_engine2`, `in_reactor`, `in_reactor2`, `in_fuel`, `in_machine`,
`in_cargo`, `in_cargo2`, `in_ramp`, `in_atrium`, `in_atrium2`, `in_habitat`,
`in_room`, `in_lobby`, `in_stair`, `in_command`, `in_bridge`, `in_bridge2`,
`det_console`, `det_wall`, `det_crate`, `det_floor`, `det_pipe`, `det_door`,
plus `dbg_*` diagnostics.

Debug flags: `--flat` (grey override), `--norm` (normal visualiser),
`--graywall`, `--nohull`, `--noshell`, `--nolight`, `--noao`,
`--only=<substr>` (isolate meshes by name), `--mark=<matkey>` (paint a
material magenta), `--dump` (per-material vertex bounds in the habitat
corridor volume).

## Ship layout

* **Hull**: 300 m superellipse envelope (`hull_w` beam × `hull_e` exponent,
  both z-varying). Bow bridge viewport, atrium skylight and habitat portholes
  are carved by `_hole()` in the grid builder. Five lathe-built engine bells
  with emissive throats, keel/dorsal spine greebles, radiator fins, comms
  masts, running lights and raised block-glyph "ISV MERIDIAN" name plates.
* **Inner pressure shell** (`build_inner_shell`): dark inner skin so seams /
  gaps read as structure, not starfield.
* **Interior**: 11 zones along a ~279 m route (stern → bow):
  engine hall (sunken drive trench, thrust pylons, plasma conduits) →
  reactor chamber (torus + ring catwalk) → fuel gallery → machine corridor
  (6 side rooms) → cargo hold (crate stacks, gantry crane, ramp) →
  atrium (skylight, mezzanine balcony, holo obelisk) → habitat spine
  (15 side rooms: mess, gym, galley, med, lab…) → lobby (desk, turnstiles)
  → grand stair → command corridor (6 rooms) → bridge (wrap viewport,
  console arc, holo table, captain's chair).
* **Side rooms** are low-detail by design; the main route is the showcase.

## Materials (all procedural)

`hull` (panel field + seam grime + rivets + accent band), `wall_a/b/c`
(panel system, kick plate, crown trim, ribs, bolts, cool-alt panels),
`floor_a/b/c`, `ceil`, `metal_a..d` (welded structure / enamel / brushed
alloy / copper), `dark`, `crate`, `hazard`, `fabric`, `glass`, `screen_a..c`,
`u_light`, `u_light_c/r/o`, `u_segm`, `u_chev`, `plasma`, `holo`, `plant`,
`sky`. Shared hash/noise/pattern helpers in `gfx/common.gdshaderinc`.

## Engineering notes

* `GeoKit` batches everything per material key → ~30 draw calls for the
  whole ship, ~99 k tris, builds in < 1 s.
* Doors are `metal_d` leaves spanning the full wall depth with lit jamb
  strips + transom so they read at any distance and angle.
* `cull_disabled` is set on the opaque shaders: kit-built analytic shells
  submit both winding conventions in places, and single-sided culling
  caused missing faces (e.g. whole upper hull).
* METALLIC is kept low (0.04–0.12) — with no reflection probes, high
  metallic mirrors the black sky and renders unlit.

## Known limitations

* `--shot` capture is CPU-window based; on a loaded GPU it may emit an
  occasional under-dimensioned frame — re-run the shot.
* Side-room furnishing is deliberately sparse (low-detail branches).
* No player collision/navigation — this is a flythrough + still-shot build.
