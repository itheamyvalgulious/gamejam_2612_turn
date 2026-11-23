# SHARD // PHANTOM

A code-generated modular teleporting enemy for a cyberpunk game.  Every mesh,
material, shader, animation and effect is emitted from pure math at runtime:
no imported models, textures, fonts or audio.

- **Engine**: Godot 4.7.2, Forward+ (Vulkan), desktop 1600×900
- **Scene**: `res://scenes/studio.tscn` (orbit camera + live tuning)
- **Character**: `res://scenes/character.tscn`
- **Companion docs**: `README_kit.md` (generic studio contract), `renders/ACCEPTANCE.md`

```bash
cd main/content/enemies/mobs/shard_phantom
./run.sh                                  # interactive studio
DISPLAY=:10 godot --path . res://scenes/shots.tscn   # kit contact sheet
DISPLAY=:10 godot --path . res://scenes/perf.tscn    # fps probe (prints avg)
DISPLAY=:10 godot --headless --path . --script res://scripts/contract_test.gd  # contract test
```

![hero](renders/hero_three_q.png)

---

## 1. Concept

SHARD // PHANTOM is a slim hovering construct wearing a body made of dozens of
loose machined chunks.  Each chunk is a separate module with its own
micro-thruster; an inner frame holds their formation.  When something looks at
it, the body bursts into a cloud of shards, streams to a new position, and snaps
back together.  The head is a compact machined **camera**: one large recessed
orange-red optic in a deep barrel (aperture/iris rings, flat glass, hood, dark
cavity) — no eyes, mouth or V slit.  It gimbals with the head joint to track the
camera.  The palms are launchers.  Palette: near-black matte metal, deep crimson secondaries,
orange-red energy.  It lives on the same dark stage as `T4 // VESPER`, but its
energy is red-orange and its motion is horizontal and abrupt.

Silhouette targets: 1.60 m tall, 0.20 m hover above the stage plate, 0.52 m
shoulder span, a narrow waist, long pointed feet, a heavy pauldron mass and a
small focal mask.  `scripts/sole_audit.gd` measures the real lowest geometry:
min sole-to-stage gap 0.2066 m in idle, 0.2094 m in walk, 0.2094 m in attack.

---

## 2. Controls

| Input | Action |
|---|---|
| LMB / RMB drag | orbit camera |
| wheel | zoom |
| `F` | reset camera |
| `H` | hide studio UI + character overlay |
| `SPACE` | play / pause |
| `B` | blink (fast disperse→reform by `teleport_distance`) |
| `N` | dispense (disperse by `teleport_distance`, hold, auto-reform) |
| `M` | reform |
| `G` | toggle GAZE REACTIVE |

The character overlay (top centre) also has BLINK / DISPENSE / REFORM buttons, a
GAZE REACTIVE checkbox and a live state readout.  Because the studio is not a
follow-cam, a jump longer than 1.6 m widens the orbit view once so both the
start and the destination stay framed (skipped in shot mode).  The studio panel on the right
contains ANIM / PARAMS / JOINTS / INFO tabs exactly as defined in
`README_kit.md`.

---

## 3. Modular anatomy

The body is `90` modules at the default (`module_count` 60–90, step 2; below
75 chunks the remaining plates are auto-scaled up so coverage holds).  The
authored slot pool has 92; every limb row (front/side/back) is present at the
default, and only the two decorative toe plates fall outside the 90-module cap.  Each
module is a chamfered plate / trapezoid / crystal shard (4–16 cm after the
`module_size` scale, clamped) with a tiny thruster on the inner face and an
optional outer bleed jet.

Hierarchy of masses: two large chest bands, shoulder caps + arm tubes, a
pelvis belt + tassets, a long segmented leg tube, and a compact camera head.  A dark
inner shell and a thin frame (spine, ribs, limb rods, joint discs, telescoping
neck/waist) show through 1–2 cm seams so the body never reads as disconnected
floating tiles.  `frame_visibility` scales the frame; during dispersal it
retracts and hides completely.

### Module → joint map

| joint | modules | notes |
|---|---|---|
| `Chest` | 12 chest tiles (2 bands × 6) | V opening at the sternum |
| `Spine` | 4 abdomen tiles | front and side, back is the carapace |
| `Pelvis` | 6 tiles (front, hip tassels, rear) | modular belt + tassets |
| `Head` | 10 housing tiles | angular armor/tiles around the single camera optic |
| `Shoulder_L/R` | 6 each (3-sided 2-row tube) | shoulder cap is frame |
| `Elbow_L/R` | 6 each | 3-sided 2-row tube |
| `Wrist_L/R` | 1 each | back-of-hand plate; palm is frame |
| `Hip_L/R` | 6 each | 3-sided 2-row thigh tube |
| `Knee_L/R` | 9 each | 3-sided 3-row shin tube |
| `Ankle_L/R` | 2 each | pointed foot wedge plates |

All naming and counts come from `PhantomRig._generate_slots()`; mirrored slots
are generated from the left side so the body stays symmetric at every count.
`param_specs()` also exposes `module_count`, `module_size`, `module_gap`; a
rebuild preserves the current joint pose (the swarm state snaps back to
ASSEMBLED, documented under known limits).

---

## 4. Rig

Skeleton (each a `Node3D`, pose applied as `Basis = Rx(pitch)·Ry(yaw)·Rz(roll)`):

```
Pelvis ─ Spine ─ Chest ─ Neck ─ Head
                  ├─ Shoulder_L ─ Elbow_L ─ Wrist_L ─ Finger_L
                  └─ Shoulder_R ─ Elbow_R ─ Wrist_R ─ Finger_R
       ├─ Hip_L ─ Knee_L ─ Ankle_L ─ Toe_L
       └─ Hip_R ─ Knee_R ─ Ankle_R ─ Toe_R
```

Design dimensions (metres, scale `height/1.60`):

| segment | length |
|---|---|
| pelvis → sole | 0.92 |
| thigh (hip→knee) | 0.34 |
| shin (knee→ankle) | 0.42 |
| upper arm / forearm | 0.26 / 0.24 |
| foot blade | ≈0.16 |

Joint limits are real and clamped in `set_joint`; the JOINTS tab exposes
pelvis yaw/pitch/roll/height, spine, chest, neck, head, both shoulders, elbows,
wrists, finger curls, hips, knees, ankles and toes.  Editing a joint pauses the
clock and enters a manual pose mode; pressing an anim button resumes authored
motion.  The idle pose is a solved 2-bone behind-the-back clasp (forearms angled
inward, palms facing back), not a baked asset.

---

## 5. Animations

| clip | duration | loop | notes |
|---|---|---|---|
| `idle` | 6.00 s | yes | hover bob 8–11 mm, module breath 3 mm, servo head scan + camera tracking, signal blinks |
| `walk` | 2.80 s × 1.2 / walk_speed | yes | in-place float glide; equivalent ground speed 1.2 m/s; feet never touch, hands behind back; torso stacked upright (`walk_lean` default 0°, range -4..8; the old default 4° produced ~6.6° cumulative forward lean) |
| `attack` | 1.02 s (params sum) | no | anticipation → raise → charge → fire → recoil → retract |
| `disperse` | `stagger + 1.16·fly_time + 0.45` | no | burst + travel + hold in cloud |
| `reform` | `1.1·reform_time + 0.33` | no | converge + overshoot + settle |

Attack timeline (defaults): raise 0.26, charge 0.20, fire hold 0.16, retract
0.40.  `attack_anticipation` adds a pull-back before the swing;
`attack_overshoot` overshoots the aim before settling.  The right arm points at
the active camera by default (`aim_at_camera = 1`), with a 22° yaw cap and a
pitch clamp so it stays near horizontal.  Set it to 0 to aim straight forward
(used for side-on render presentation).  The left arm keeps the clasp.

`idle` and `walk` honour `set_loop()` (and default to looping); `attack`,
`disperse` and `reform` always clamp at their end.  Every periodic pose term and
the module breathing use the clip duration, so the loop seam is continuous —
the measured max module-position delta between `t=0` and `t=duration` is
**0.000000 m** for both idle and walk (`scripts/loop_soak_test.gd`).  A 10 s idle
soak wraps once and keeps animating; walk wraps three times.

Every pose is a closed-form function of time.  `set_anim_time()` re-applies the
whole joint dictionary synchronously, so `idle` / `walk` / `attack` are fully
deterministic.  `disperse` / `reform` are deterministic **given the snapshot
captured at trigger time**; scrubbing re-evaluates the stored start/end
snapshots, so a scrub backwards/forwards reproduces the same path (the snapshot
itself depends on the pose at the trigger — the documented exception).

---

## 6. Dispersal / reform

State machine (`field.state`):

```
ASSEMBLED ──disperse_to() / blink / gaze──▶ DISPERSING ──▶ FLYING
    ▲                                                      │
    └──────────────── REFORMING ◀──reform() / auto─────────┘
```

`disperse(src, dst)` in the demo moves the body by `teleport_distance` (default
5.0 m, range 0–12 m) and holds the cloud until `reform()` is called.  BLINK and
the gaze trigger both use the same parameter.  API:

```gdscript
func disperse_to(target: Vector3) -> void   # target is a WORLD ground position
func reform() -> void
func is_assembled() -> bool
```

Each module `i` gets a delay `d_i` from a shuffled stagger, a flight time
`f_i ∈ [0.78, 1.16]·fly_time`, and a destination on a jittered golden-angle
shell around the destination chest point, with radii `0.58–1.0 × spread_radius`
and the vertical axis compressed.  Its path is a quadratic Bézier with a
dropped/curved control point:

$$
P_i(u) = \operatorname{bez}\big(S_i,\; C_i,\; T_i,\; u\big),\qquad
u = \operatorname{clamp}\!\left(\frac{t-d_i}{f_i},0,1\right)
$$

$$
C_i = \frac{S_i+T_i}{2} + \hat{y}\,a_i + \hat{\tau}_i r_i
$$

where `a_i` is the vertical arc (`arc_height`) and `\hat{\tau}_i r_i` a random
tangential lateral bow.  Modules spin around their own random axis at
`spin_speed`, and once in the cloud slowly orbit the centre.  Mid-flight the
cloud radius is 1.4–2.5 m, deliberately far from the body shape.

Reform snapshots each module's current transform, then converges over 86 % of
its reform time with a smoothstep, applies a terminal overshoot
`settle_overshoot` along the radial direction and a damped settle:

$$
P(u) = \begin{cases}
\operatorname{lerp}(S,T,\operatorname{smoothstep}(u/0.86)), & u \le 0.86 \\
T + \hat{n}\,\delta\,\sin\!\left(\pi v\right)(1-v), & u>0.86
\end{cases}
$$

with `v=(u-0.86)/0.14` and `\hat{n}` the direction from the start to the slot.
The frame telescopes in during flight and expands back only near the end of the
reform.  A dashed destination ring is drawn on the floor from the start of the
dispersal so the eye can read the jump; it contracts and fades during the
reform.

---

## 7. Gaze trigger

`GAZE REACTIVE` is **OFF** by default.  When on, `gaze_distance` (3–16 m) and
the active `Camera3D` frustum are tested against the chest point.  Being seen
while ASSEMBLED and idle/walk starts a blink away, with `gaze_interval`
cooldown.  The toggle is available as a 0/1 PARAM row, the overlay checkbox and
the `G` key.  Current gaze state is shown in `rig_debug()`.

---

## 8. Attack / shuriken

The right palm is a launcher: a machined ring + iris shader that charges from
0 → 1 (the head optic also flares).  At the fire moment a 4-blade energy star
spawns from the palm with a hot core, additive blade shader, a readable spin,
slight gravity arc and a crossed additive trail.
The spin is **480 deg/s about the star's own normal** (local +Z, i.e. back along
the flight axis, applied in local space) with a 2-4 deg local precession so the
disc plane tilts as it turns.  One blade is 24% longer than the other three and
carries a hot tip bead — a plain 4-blade star is 90-deg symmetric, so this is
what makes the rotation visible.  At 0.05 s steps the orientation advances
**24 deg/frame** (`renders/shuriken_spin_strip.png`).  `burst_count` fires 1–3 stars with a
yaw spread.  Speed, size, spin, spread, trail life and the raise/charge/fire/
retract windows are all parameters.  The star is deterministic in the anim
clock: position `= p0 + v t + ½ g t² + side·curl·t²`, spin `= ω t`; scrubbing
the attack re-shows the same projectile and trail.  When the clip clamps at its
end the star keeps flying in world space for its full 1.05 s life (the post-clip
age advances with real time) and then hides — no frozen projectile remains.
`set_loop()` state matches the studio checkbox per clip: idle/walk checked,
attack/disperse/reform unchecked.

---

## 9. Shaders / FX

| shader | use |
|---|---|
| `module_shell.gdshader` | smooth matte metal for both modules and frame: +-2% panel-scale albedo mottling, per-panel tint, darkened corners, faint desaturated patina in crevices (no orange rust); low-frequency roughness +-0.05 around 0.52-0.65, sparse long anisotropic scratches (roughness/specular + a slight albedo lift, edge-biased), very subtle micro-normal; slight edge lightening; metallic 0.9 / specular 0.35. Module mode adds the hairline orange chamfer/signal/phase emission |
| `lens.gdshader` (kit) via `PM.head_optic()` | the head camera: large recessed orange-red iris, aperture rings, scan; `alert` flares with the attack charge |
| `palm_emitter.gdshader` | palm housing, containment ring, 12 iris blades, hot core, charge |
| `charge_orb.gdshader` | additive sphere charge orb (no billboard square; hidden unless attacking) |
| `shuriken.gdshader` | additive 4-blade star, rotating lobe pattern, hot core |
| `energy_trail.gdshader` | short additive trail ribbon for the star |
| `micro_thruster.gdshader` | per-module inner plume, MultiMesh + INSTANCE_CUSTOM seed/boost |
| `vent_plume.gdshader` | frame attitude-jet plumes (shoulders, spine, hips, calves, soles) |
| `motion_streak.gdshader` | flight motion streaks behind every chunk while dispersed |
| `assembly_ring.gdshader` | dashed destination guide ring |
| `ground_glow.gdshader` | tight warm hover pool |
| `soft_shadow.gdshader` | texture-free radial contact shadow |

The head optic, palm emitters, thruster nozzles and a thin sternum seam are the
only emissive body elements.  All plumes flicker per-instance; the swarm boosts the
plume size/brightness and adds phase edges.

---

## 10. Parameters

**BODY** height, hover_height, shoulder_width, limb_girth, head_size,
module_count, module_size, module_gap, frame_visibility

**IDLE/WALK** hover_bob, module_breath, idle_head_turn, walk_stride, walk_speed,
walk_lean

**ATTACK** raise_time, charge_time, fire_time, retract_time, attack_anticipation,
attack_overshoot, shuriken_speed, shuriken_size, shuriken_spin, burst_count,
shuriken_spread, aim_at_camera

**SWARM** spread_radius, fly_time, stagger, arc_height, spin_speed, reform_time,
settle_overshoot, teleport_distance (0–12 m, default 5.0)

**FX** hover_thrust_power, hover_glow, thruster_size, thruster_intensity,
glow_intensity, trail_life

Hover propulsion: **6 dedicated nozzles** plus the per-module micro-thrusters,
and none between the legs: 2 larger back lift jets on the upper/mid back aimed
down/outward (52 mm x 190 mm at power 1), 2 small rear-calf jets (28 x 90 mm),
2 sole jets (40 x 140 mm).  They scale 0.55-1.45x over `hover_thrust_power`
0..3 and are hot orange-red.  `hover_glow` scales the stage-only downward wash
spot and the flickering ground pool under the body; the crotch stays clean from
the front and 3/4.

**GAZE** gaze_reactive, gaze_distance, gaze_interval

Geometry rows rebuild immediately and re-apply the current joint pose.
`module_size` is a **nominal** parameter (0.10 m default in this build; the
audited copy still read 0.125 m) and `module_gap` both drive the slot generator
before `regenerate_slots()`.  Because the authored slots have mixed shapes and
every plate is clamped to 4–16 cm, the measured average max-module dimension at
the default is **0.1087 m** — do not compare the nominal value 1:1 with the
measured average.  Verified max-module
dimension averages: **0.0459 / 0.1087 / 0.1504 m** for module_size 0.04 / 0.10 /
0.16, and **0.0964 / 0.1087 / 0.1232 m** for module_gap 0.008 / 0.018 / 0.030.
`thruster_intensity` scales plume size and additive intensity (0 = no plume,
3 = strong; verified in the calf close-up pair).

---

## 11. Performance

Measured at **1600×900**, Forward+, MSAA 2×, SSAO, glow, on this machine
(GTX 1650, Vulkan 1.4):

| | value |
|---|---|
| studio (vsync) | **60 fps** stable |
| vsync disabled | **117.5–117.9 fps** average over 6 s (procedural metal + SSR + hover wash) |
| draw calls | 351 |
| primitives | 42 912 |
| modules | 90 (60–90 range) |

Modules share 5 mesh variants + one material with per-instance uniforms; all
plumes are one `MultiMesh` draw call, as are the flight streaks.  The scene
boots with zero script / shader errors.

---

## 12. Renders

Full acceptance gallery and per-image checklists: **`renders/ACCEPTANCE.md`**.

- `renders/hero_front.png`, `hero_three_q.png`, `hero_back.png`, `hero_low.png`
- `renders/gameplay_5m.png`
- `renders/contact_idle.png`, `contact_walk.png`, `contact_attack.png`
- `renders/blink_strip_three_q.png`, `blink_strip_front.png`
- `renders/attack_side.png`, `attack_charge.png`, `shuriken_spin_strip.png`
- `renders/hero_side.png`, `renders/walk_side_strip.png`
- `renders/closeup_head.png`, `closeup_hover.png`, `closeup_metal.png`, `attack_muzzle.png`,
  `closeup_shoulder_thruster.png`, `closeup_calf_thruster.png`,
  `closeup_modules.png`, `closeup_palm.png`

---

## 12b. Metal / reflection / hover notes

The module shell shader is fully procedural (no textures) and runs on both the
modules (`style=0`) and the frame (`style=1`):

- **Albedo**: +-2% panel-scale mottling, per-panel tint (3 near-black greys,
  oxblood, deep red, warm graphite) and per-panel brightness, darkened corners,
  and a very desaturated grey-brown patina in crevices/low areas.  The plate
  base colour stays clean; the red plates are desaturated and oxidized, never
  orange rust, and there is no dense per-pixel grain.
- **Roughness**: base 0.54 (modules) / 0.52-0.58 (frame), one low-frequency
  octave pair at +-0.05 (18 / 55 cycles per metre), so the specular sheen stays
  smooth and broad rather than speckled.
- **Scratches**: three sparse anisotropic streak layers with independent random
  orientations; `fx_seed` gives roughly one scratched plate in two, biased to
  the chamfer/edges and protruding modules.  They are long and thin, affect
  roughness/specular and add a small albedo lift so they catch the eye, and are
  tuned to read at 1-2 m.  There is no high-frequency pitting field.
- **Micro-normal**: two very low-amplitude tangent-frame perturbations at broad
  scale (+-0.03) only break the top of a highlight; they do not sandpaper the
  face.
- **Edge wear**: the 3.5 mm chamfer strip and grazing fresnel get a slight
  albedo lift and a polish; it is not emissive and does not read as a rim.
- Metallic 0.9, specular 0.35, matte.

The studio enables Forward+ **SSR** and adds a **ReflectionProbe** at the hero
position with `cull_mask = 2` (stage only), so the black chunks pick up the
orange ring and neon bars instead of staying flat.  The dedicated
`closeup_metal` still uses a temporary grazing inspection key at 1.25 m (22°
lens) to make the micro-detail legible at 1600x900; it is removed after the
shot and is not part of the scene.

Hover: see §10; the downward wash is a stage-only SpotLight3D under the body
(cull mask 2) plus a flickering additive pool; the flames originate on the back,
rear calves and soles.

---

## 13. Fixes / deviations from the kit

Two generic kit bugs were fixed and are documented here:

1. **`scripts/studio.gd` camera**: `camera.look_at_from_position(offset,
   Vector3.ZERO, UP)` uses global coordinates and ignored `cam_pivot`, so every
   orbit view actually looked at the world origin.  It now sets
   `camera.position = offset` and `camera.basis = Basis.looking_at(-offset.normalized(), UP)`.
   The home/shot presets were retuned for the 1.6 m floating subject
   (target y 0.95, distance 4.2–4.9).
2. **`scripts/kit/param_panel.gd`**: when the new animation duration was shorter
   than the previous one, assigning `max_value` clamped the slider and emitted
   `value_changed`, which called `set_anim_time()` and instantly skipped e.g. the
   reform clip.  The max update is now done with signals blocked +
   `set_value_no_signal`.  The LOOP checkbox is also synced to the character's
   per-clip loop flag each frame.  (The parent agent additionally patched the
   generic panel's row overflow so the LOOP/arrows are not clipped; kept.)

Art-direction change (not a bug): the stock stage leaves the centre dark, so a
**layer-masked character light rig** was added to `studio.gd` (warm front key,
cool front fill, purple back rim, warm back kicker, floor bounce).  The stage's
render layer 2 is excluded from these lights (`light_cull_mask = 1`), keeping
the background and floor pools dark while the character reads.  The stage's own
lights were dimmed.  This only affects the studio scene, not the character.

---

## 13b. Hover / sole verification

The stage plate top is 0.047 m above the world origin.  The foot geometry
extends 0.0288 m below the design sole plane, so the rig is lifted by that
constant (`SOLE_DROP`) and `hover_height` is the **actual sole-to-stage gap**.
`scripts/sole_audit.gd` walks the module + frame AABBs over 41 samples per clip:

| clip | min sole Y (m) | min gap (m) |
|---|---|---|
| idle | 0.2536 | **0.2066** |
| walk | 0.2564 | 0.2094 |
| attack | 0.2564 | 0.2094 |

All three stay above the required 0.18 m.  `rig_debug()` reports
`HOVER GAP 0.200 m (min)` and the current nominal `SOLE Y`, not the root height.

---

## 14. Known limits

- **Dispersal / reform scrubbing**: deterministic only from the snapshot taken
  when the clip is triggered.  A rebuild of the modules (module_count/size/gap
  or body proportions) snaps a mid-flight swarm back to ASSEMBLED.
- **Aim**: the attack points at the active camera by default, so a contact-sheet
  view looking down the throw line sees the projectile foreshortened; the
  `attack_side` still sets `aim_at_camera = 0` for a side-on presentation.
- **Arm silhouette**: the upper arm / shoulder plate cluster is busy at 3/4;
  this is the part of the design that would get the next art pass.
- **Head read**: the head is a single camera optic by design.  The lens bloom is
  strong at very close range but the recessed barrel/aperture keeps it reading
  as a camera, not a face.
- The shuriken is hidden when another animation is selected; during the attack
  it persists in world space for its full life after the clip clamps.
- The clasped hands sit 0.08 m apart; finger claws can touch at the tips, and
  the layered shoulder plates can touch in extreme arm poses.  No z-fighting;
  the claims above are scoped to the delivered idle/walk/attack poses.
- Contact sheets are deliberately dark (the stage is a night scene); material
  detail is easier to judge in the close-up stills.

---

## 15. File map

```
scripts/character.gd              contract, params, animation math, swarm state,
                                  gaze, overlay, FX
scripts/phantom/phantom_rig.gd    skeleton, frame, hands/mask, slot authoring
scripts/phantom/module_field.gd   module instances, dispersal/reform sim, plumes,
                                  streaks, plumes MultiMesh
scripts/phantom/energy_shuriken.gd analytic star + trail
scripts/phantom/phantom_kit.gd    extruded plates/shards/stars/plume meshes
scripts/phantom/phantom_materials.gd materials + per-instance palettes
scripts/render_suite.gd           contact / blink / hero / closeup render modes
scripts/perf_probe.gd             6-second fps probe
scripts/sole_audit.gd             sole-to-stage gap audit (idle/walk/attack)
                                  also reports HOVER GAP from rig_debug
scripts/contract_test.gd          headless contract smoke test (anims, scrub,
                                  params, joints, disperse/reform, loop flags,
                                  post-clip projectile)
scripts/loop_soak_test.gd        10 s loop soak + loop-seam delta measurement
shaders/*.gdshader                the visual language listed in §9
(no external textures; metal is procedural)
```