# KIT // procedural character studio

This folder is a **starter project** for one code-generated cyberpunk enemy.
Copy it, then own everything inside your copy. It contains no character art —
`scenes/character.tscn` is yours to write.

It is built and verified on **Godot 4.7.2 / Forward+ (Vulkan)** on this machine.
Always run with:

```bash
cd <project>
DISPLAY=:10 XAUTHORITY=$HOME/.Xauthority godot --path .            # interactive studio
DISPLAY=:10 XAUTHORITY=$HOME/.Xauthority godot --path . res://scenes/shots.tscn   # contact sheet
```

`DISPLAY=:10` is a real X server on this box; Vulkan works there. Screenshots via
the in-game `F12` key, or the shot runner. **Never** claim a visual result without
opening the rendered PNG yourself (the `read` tool can display images).

---

## 1. Character contract

`scenes/character.tscn` root = `Node3D` with a script exposing exactly these:

```gdscript
var current_anim: String

func anim_names() -> PackedStringArray          # ordered, e.g. ["idle","run","attack","defend"]
func play_anim(name: String) -> void            # reset to t=0, playing
func set_playing(v: bool) -> void
func is_playing() -> bool
func anim_time() -> float
func set_anim_time(t: float) -> void            # deterministic evaluation (scrub)
func anim_duration() -> float                   # of the current anim
func set_anim_speed(v: float) -> void
func anim_speed() -> float
func set_loop(v: bool) -> void
func is_looping() -> bool

# Tuning rows: {group, key, label, min, max, step, value}
func param_specs() -> Array                     # body/weapon/anim params
func set_param(key: String, value: float) -> void
func get_param(key: String) -> float
func joint_specs() -> Array                     # direct joint-angle controls
func set_joint(key: String, value: float) -> void
func get_joint(key: String) -> float

func rig_debug() -> Dictionary                  # arbitrary readouts for the INFO tab
```

Rules:

- The character owns its clock: `_process(dt)` advances time when playing;
  the studio polls `anim_time()`. `set_anim_time()` must fully re-pose the rig.
- The studio (this file's `scripts/studio.gd` + `scripts/kit/param_panel.gd`)
  builds the whole UI, camera, lighting and overlay automatically. Don't edit
  them unless fixing a generic bug (document it in your README).
- `param_specs()` must include, at minimum: body proportions, weapon dimensions,
  and **per-animation lead-in / follow-through / overshoot** controls.
  Geometry-changing params must rebuild immediately and preserve the current pose.
- `joint_specs()` must be a real rig: setting joint values alone can hit any pose
  used by the animations. This proves the model is joint-driven, not baked.
- No external assets. No `.glb`, `.obj`, `.png` textures, fonts, audio.
  Everything is math: ArrayMesh, StandardMaterial3D, ShaderMaterial, particles.

---

## 2. Shape language (hard constraint)

The robot surface vocabulary is **spherical arcs + flat planes only**:

- Use `MeshKit.arc_shell`, `dome`, `disc`, `ring`, `plate`, `beam`, `katana`.
- No smooth capsules, no lathed organic cylinders, no muscle volumes.
- Chamfers and bevels are flat facets (the kit's `plate`/`disc`/`beam` are already like this).
- No wires, no seam lines, no panel-gap decoration, no exposed cables.
- Read as machined, sealed, high-purity hardware: **matte metal**, not chrome,
  not gloss plastic. Roughness generally 0.35–0.60, metallic 0.85–1.0.

`MeshKit.katana()` gives the curved katana volume (sori) with a lens cross section.
`MeshKit.ribbon_cross()` + `lightning.gdshader` gives 3D arc bolts.
`MeshKit.dome()` gives radial UVs for shield/lens shaders.

---

## 3. Studio features you get for free

- Orbit camera: LMB/RMB drag, wheel zoom, `F` reset. The shot runner has
  `three_q / front / side / back / low / top` presets.
- Environment: dark stage, neon rim lights, procedural sky reflections, ACES,
  bloom, SSAO, subtle fog, screen grade overlay (vignette/scan/grain/CA).
- Live numeric entry: `SpinBox` rows grouped by `group`, collapsible.
- Playback: anim buttons, timeline scrub, speed, loop, pause.
- INFO tab: fps / draw calls / primitives + your `rig_debug()` dictionary.

---

## 4. Visual acceptance (commercial bar)

A render is not acceptable unless **all** of these read clearly at 1600×900:

1. **Silhouette** at 3/4 and front: instantly reads as the intended enemy,
   with a strong non-human silhouette. No "box with arms" look.
2. **Material**: matte metal with controlled speculars; black/red palette;
   no plastic sheen, no chrome mirror, no noisy grunge.
3. **Hierarchy**: one clear focal element (chest optic / weapon), secondary
   masses supporting it, tertiary details small and sparse.
4. **Clean surfaces**: no z-fighting, no inverted normals, no gaps at joints,
   no parts intersecting in any animated pose (inspect the contact sheet).
5. **Motion**: contact sheet must show readable anticipation / impact /
   follow-through; run cycle must plant feet (no skating); idle must have
   subtle servo/breath life, not a frozen statue.
6. **Effects**: shader-driven, tasteful, not covering the model. Arc sword,
   shield rings, thrusters must be legible at gameplay distance.
7. **Perf**: ≥ 60 fps at 1600×900 on this machine in the studio scene
   (GTX 1650, Forward+). Print the measured avg fps in your README.

Also verify at least once at a **gameplay camera distance** (~4–6 m) and
against a bright rim light, where thin geometry often disappears.

---

## 5. Render/QA workflow

```bash
# all animations, 3 views, 4 time samples each
DISPLAY=:10 SHOT_VIEWS=three_q,front,side godot --path . res://scenes/shots.tscn

# one anim, more time samples
DISPLAY=:10 SHOT_ANIMS=attack SHOT_TIMES=0,0.15,0.3,0.45,0.6,0.75,0.9 \
  godot --path . res://scenes/shots.tscn
```

Contact sheet helper (needs ffmpeg):

```bash
ffmpeg -pattern_type glob -i 'renders/contact/*.png' -filter_complex \
  "scale=480:-1,tile=4x3" -frames:v 1 renders/contact_sheet.png
```

Look at every sheet with your multimodal vision. Fix what looks wrong, re-render.
**Numbers alone (bone count, range, fps) never prove visual quality.**

---

## 6. Project hygiene

- `README.md` in your project: art breakdown, rig/joint map, animation timing
  tables, parameter list, measured perf, screenshots, known limits.
- Keep `renders/` (generated, not source) out of any commit if a repo exists.
- No leftover probes or dummy geometry in the main scene.
- Project must boot clean: zero script errors / shader errors in the console.

---

## 7. Reference material on this machine

- `/dat/projects/gamejam_2612_turn/basic/character/` — prior procedural mech:
  mesh kit, materials, IK arms, foot-planted gaits, animation math, renders.
- `main/content/levels/actdemo/` — cyberpunk alley art
  direction, shaders (`gfx/*.gdshader`), hit/VFX language, parameter panel.
- `basic/character/renders/contact_sheet.png` — target level of finish.

Reuse **ideas and math** freely; the two projects above are in the same family.
Do not copy their whole rig wholesale — your enemy needs its own anatomy.