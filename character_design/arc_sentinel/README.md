# ARC // SENTINEL v2

**Two-wheel balancing war machine — a fully procedural Godot 4 character.**

Everything in this project is generated from code at runtime: meshes, materials,
shaders, animation, collision proxies, IK and VFX. There is no imported model,
texture, font or audio file. Open `scenes/studio.tscn` for the live studio:
orbit camera, spin-box tuning, animation transport and a joint-by-joint posing
tab.

```bash
cd arc_sentinel
./run.sh                       # DISPLAY=:10 by default
# or
DISPLAY=:10 godot --path .
```

---

## 1. Concept

A compact industrial sentinel balanced on two solid, independently suspended
wheels. The body is a short cylindrical pressure hull whose axis is
front/back. The front carries a large camera objective — the machine's only
"face"; the rear has a domed service bulge and a mechanical shield hook; the
left flank carries the sword sheath. There is no head.

* **Two solid wheels**, no spokes, each wrapped in a full ring of raised metal
  tread plates (friction + armour) and a glowing outboard ring. Each wheel is
  carried by a telescopic strut with the coil spring sleeved directly on the
  rod; the whole strut compresses/extends with the body while the axles stay
  on the ground. No lever arm crosses the wheel face.
* **Two flexible arms**, each a chain of three visible ball joints
  (shoulder / elbow / wrist) plus the tool segment. Left wrist ends in the
  shield mount; right wrist ends in a **short arc-generator head** (no hilt)
  that projects the electric sword.
* **Black + orange-red machined metal.** Metallic PBR with procedural brushed
  streaks, roughness breakup, sparse scratches, pitting and edge wear. The
  electric sword, shield field, iris and seams are the only saturated light.
* **Ball-turret camera eye.** A small ball housing sits just outside the hull
  front; the barrel retracts only ~0.08 m (the glowing eye stays the outermost
  part) and the static iris/socket closes the hull behind it. During both
  attacks the ball compensates for torso motion to keep looking forward.

Dimensions (defaults): wheel radius 0.325 m, wheel centres x ±0.45 m, body root
y 0.62 m, hull radius 0.225 m, shoulder pivots ±0.27 m / y 1.10 m, upper arm
0.48 m, forearm 0.40 m, tool 0.13 m (reach 1.01 m), shield radius 0.31 m,
electric blade 1.03 m, overall height ≈1.4 m.

## 2. Controls

| Input | Function |
| --- | --- |
| mouse drag | orbit |
| wheel | zoom |
| `F` | reset view |
| `H` | hide/show UI |
| `Space` | play/pause |
| `F12` | screenshot |
| `1` … `8` | rest / idle / walk / attack / attack_up / defend / draw / sheathe |

The right panel has `ANIM`, `PARAMS`, `JOINTS`, `INFO`. Every numeric row is a
real SpinBox. `JOINTS` can pose the character one joint at a time. In
`PARAMS → ANIM // DEFEND`, `threat side` selects the defend case: 0 = front-left
(shield), 1 = front-right (sword); press `6` again to replay the block.

**Transition state machine.** `rest` and the drawn states are connected only
through `draw` / `sheathe`; a one-shot (`attack`, `attack_up`, `defend`, `draw`,
`sheathe`) is never cancelled mid-swing. A request made during a one-shot is
queued and starts after it finishes. This is what guarantees that a sword swing
cannot be cross-faded through the hull. Idle/walk crossfade normally; all
one-shots start and end on the idle base pose.

## 3. Animation set

| clip | duration | loop | content |
| --- | --- | --- | --- |
| `rest` | 4.0 s | yes | sword generator docked in the left sheath (blade off), shield hung on the rear hook, arms folded low, torso twisted 35° toward the sheath |
| `idle` | 3.2 s | yes | deployed low guard: sword low-right, shield low-left/front, gentle balance sway |
| `walk` | 0.9 s | yes | rolling gait: one wheel revolution per cycle, suspension bob, body lean, arm counter-swing |
| `attack` | 1.45 s | no | high left-front windup → forward sweep → low right-front finish with suspension compression |
| `attack_up` | 1.50 s | no | lower-right loading motion → upper-left front cut with level optics |
| `defend` | 1.26–1.28 s | no | threat-driven block: front-left 45° ⇒ shield, front-right 45° ⇒ sword |
| `draw` | 0.90 s | no | rest → idle: shield off the back hook, sword out of the sheath, blade ignites when clear |
| `sheathe` | 0.85 s | no | idle → rest: blade off before the generator enters the sheath, shield back on the hook |

Both attacks start and end in the deployed guard. The right elbow stays
outside the camera envelope. The body turns into each stroke, the blade
follows, and the suspension absorbs the follow-through before settling.

## 4. Block contract

There is **no guard fallback**. `defend` always resolves to one of the two
mandated effectors:

| threat | effector | result |
| --- | --- | --- |
| front-left 45° at the chest | **shield** | threat ray passes through the disc centre, miss 0.000 m, min clearance +0.013 m |
| front-right 45° at the chest | **sword** | threat ray crosses the blade, miss 0.000 m, min clearance +0.019 m |

The block pose is built once by the solver and loaded from the trajectory
table; plan time is ≤5 ms.

## 5. Solver and trajectory table

* **Analytic two-bone IK with a free swivel** around the shoulder→wrist axis
  (Korein/Badler-style). The wrist is a 3-DOF ball joint; the elbow is a ball
  joint with a pure pitch plus a twist-sharing roll. All joints are stored as
  **quaternions**, so no Euler gimbal flips can reach the rig.
* The two cuts have authored elbow and wrist guides that preserve the fixed
  arm lengths. The blade face follows the swing without sudden roll reversals.
  The optic tracks forward, and the shield path leaves room for the cut.
* Draw, sheathe, and block use Cartesian targets and collision-aware swivel
  selection. The attack paths, other one-shots, and their key poses are baked
  to data/arc_traj_v2.json. The cache signature covers geometry and the
  authored strike revision. Runtime plan times are about 1 ms per attack.
* Idle/walk/rest are solved live (small procedural targets, fixed elbow pole)
  and are also covered by the collision audit.
* Runtime smoothness: there is no periodic full-vertex radius scan or collision
  sweep. The radius is measured once per rig build and clearance once per clip
  change, so the render loop has no 0.6 s hitch. The old additive blade-core
  plane was removed; the arc field alone is the blade, and it cannot leave a
  translucent sword silhouette when a frame is long.
* The state machine tracks a logical `rest`/`drawn` stance. Requests made
  during a one-shot are queued to the latest target, and every request resolves
  through `draw`/`sheathe` when the stance changes; transitions are never
  skipped because `current_anim` still holds a previous clip name.
* The studio's PARAMS panel includes `ENVIRONMENT → ambient light / exposure`;
  the defaults are 1.25 / 1.15. They drive the WorldEnvironment live.

Collision model: capsules for the hull/camera/links/blade, discs for the
shield/wheels, spheres for the ball joints. Every pair that is not a neighbour
in the same kinematic chain is checked. Docked pairs (generator in the sheath,
shield on the rear hook) are exempt only while actually docked.

## 6. Acceptance

Run:

```bash
# full QA (collisions on every clip frame, reachable transitions, attack
# poses, both blocks, solver timing)
godot --headless --path . res://scenes/qa.tscn

# re-bake the trajectory table after changing the motion
godot --headless --path . --script res://scripts/bake_traj.gd

# motion frame strips for visual review (960×540, 16 frames × 4 views × 9 clips)
DISPLAY=:10 godot --path . res://scenes/v2_shots.tscn

# metal / camera / wheel / shield / sword closeups + full-body views
DISPLAY=:10 godot --path . res://scenes/v2_details.tscn

# mandated block renders with a ghost threat blade
DISPLAY=:10 godot --path . res://scenes/block_demo.tscn
```

Latest QA (`renders/v2/qa_report.json`): **PASS, 0 failures**.

| check | result |
| --- | --- |
| clip self-collision | rest +0.0265 / idle +0.0526 / walk +0.0407 / attack +0.0091 / attack_up +0.0080 / defend +0.0130 / draw +0.0265 / sheathe +0.0536 m |
| floor | every clip ≥ −0.0000 m |
| reachable blends | worst +0.0501 m (all state-machine-reachable transitions) |
| attack pose | high-left preparation, forward sweep, right-front-down finish |
| attack_up pose | low-right preparation, upper-left finish, forward optic |
| blocks | shield & sword both hit, no guard |
| solver | attack 1 ms, attack_up 1 ms, block ≤13 ms (baked) |
| joint speed | peak qdot 24.9 rad/s for attack, 18.3 rad/s for attack_up |

Visual evidence is in `renders/v2/`:

* `details/hero.png`, `front_full.png`, `side_full.png`, `back_full.png`
* `details/camera*.png`, `wheel*.png`, `metal.png`, `shield.png`,
  `sword.png`, `body.png`, `shoulder.png`, `rest_back.png`, `sheath.png`
* `block_left.png`, `block_right.png`
* `sheets/*.png` (all 16 frames × 4 views for every clip)
* `frames/<clip>/<view>_<i>.png` (source frames)

**Metal:** `shaders/arc_metal_v2.gdshader` is a lit PBR metal shader with
object-space brushed micro-grooves, roughness breakup, fine pitting, sparse
scratches and fresnel edge wear; SSR + a stage reflection probe supply the
environment highlights. It is deliberately tuned as dark machined metal, not a
mirror or plastic.

## 7. Known limits (honest)

* The camera stays forward during both attacks, with at most ~1° of deviation
  through the guard endpoints. Collision checks use geometric proxies.
* The baked trajectory table is bound to the default geometry signature. If you
  change hull/wheel/shield/blade dimensions, the solver rebuilds; the first
  build after such a change is seconds, not milliseconds.
* The ghost enemy blades in `block_left/right.png` are illustrative HDR
  emissive props; the actual block proof is the ray/disc/segment test in QA
  (miss 0.000 m).
* The shield is an additive hard-light field (unshaded), not a metal plate; the
  rim and struts are metal. This is the established shield style.
* Skin/metal detail is procedural but stylized; it is not a scanned 3A texture
  set.
* Seven generated texture RIDs are reported as leaked when the process exits;
  they do not affect the running scene.

## 8. Directory

```text
scenes/
  studio.tscn          interactive studio (default)
  character.tscn       contract implementation
  qa.tscn              full acceptance QA
  v2_shots.tscn        motion frame strips
  v2_details.tscn      full-body + closeup renders
  block_demo.tscn      left/right 45° block renders
  shots.tscn           generic contact-sheet runner
scripts/
  ch/arc_rig.gd        skeleton + procedural geometry
  ch/arc_kin.gd        analytic IK, swivel, collision proxies
  ch/arc_anim.gd       key poses, Cartesian trajectories, bake/load
  ch/arc_sentinel.gd   contract, state machine, FX, lens
  ch/arc_materials.gd  palette / material wiring
  ch/arc_field.gd      stochastic arc blade (ported from weapon_electricity_sword)
  ch/arc_bolt.gd       arc ribbon mesh
  ch/arc_sword_fx.gd   blade FX driver
  bake_traj.gd         offline trajectory bake
  qa.gd                acceptance checks
  kit/                 shared mesh/material/panel/studio kit
shaders/               metal, lens, shield, arc ribbon, trail, floor, grade
data/arc_traj_v2.json  baked trajectory table (~0.7 MB)
renders/v2/            final renders, sheets, frames, QA report
```

## 9. Planning references

The solver is a hybrid of classic robot-arm planning techniques:

* analytic two-bone IK with a swivel angle (Korein & Badler, 1982; Tolani,
  Goswami & Badler, 2000);
* redundancy resolved at the elbow roll so the wrist stays out of gimbal lock;
* damped-least-squares / CCD and FABRIK were considered; the analytic branch is
  used because it is exact and microsecond-scale;
* Cartesian key targets + collision-aware sampling + local time
  reparameterization (a practical simplification of trajectory optimization
  methods such as CHOMP/STOMP, Ratliff et al. 2009; Kalakrishnan et al. 2011);
* RRT/RRT-Connect (LaValle 1998; Kuffner & LaValle 2000) was not needed at this
  scale: the workspace is a small known hull and the safe transit points are
  authored in the key targets.