# LEVIATHAN // ABYSSAL WARDEN

A code-generated **final boss**: a mechanical octopus built around a **2 m
radius** armoured sphere (4 m diameter), with **eight independent jointed
chains**, a gimballed red **camera eye**, an iris shell with two phases, a red
**energy core** and a **laser**. Everything — meshes, materials, shaders,
motion, scheduling, FX — is generated at runtime. No imported meshes, textures,
fonts or audio.

| | |
| --- | --- |
| Engine | Godot **4.7.2**, Forward+ |
| Body | 2.0 m radius sphere, 4.0 m diameter |
| Limbs | 8 · alternating ~0.30 m rod + ~0.31 m ball joint, every ~0.60 m |
| Idle length | **15.0 m** (2.5× the 6 m design base) |
| Support | planted feet, **8.9–10.1 m** actual chain length |
| Attack 3 | **20 m** limb, distal band at **1.0 m**, full **360°** sweep |
| Role floor | **≥ 3 supports** while ≥ 3 limbs live; below 3 the body falls and all attack |
| Phases | 1 = camera eye through aperture · 2 = shell open, core + laser |
| QA | **61 / 61 PASS**, 0 failures · **≈8.2 ms** per 60 Hz sim step (CPU) |

---

## Quick start

```bash
cd boss
./run.sh                       # or: godot --path .
godot --headless --path . --import         # first time only
godot --headless --path . res://scenes/qa.tscn       # acceptance suite
# optional: godot --path . res://scenes/shots.tscn (no image set is shipped)
```

The default scene is `scenes/studio.tscn`. The right panel drives roles, phase,
target, limb dynamics and live parameters.

**Controls:** LMB/RMB drag orbit · wheel zoom · `F` reset camera · `H` hide UI ·
`SPACE` pause · `1`–`8` select a limb · `I` idle · `U` support · `J/K/L`
attack 1/2/3 · `C` cut a limb · `P` toggle phase · `A` auto roles · `N` move the
target · `R` reset boss · `F12` screenshot.

---

## What is on screen

### Body and shell

The body is a sphere with a **fixed rear armour shell** and an **8-blade iris**
recessed inside it. The blades slide outward and disappear under the rear
armour; a continuous machined **guide ring** follows the aperture edge, so the
opening is always a clean mechanical circle.

- Phase 1: aperture **36.3°** per side; the red camera eye is visible through a
  large camera-iris hole; the plasma core is cold.
- Phase 2: aperture **100°** per side, shell blades fully retracted, the red
  plasma core ignites, a faint **transparent containment wall** fades in, and the
  eye pod retracts/dims behind the core. The laser becomes available.

The eye is a real gimbal: a heavy ring + pitch ring + lens pod that tracks the
target inside the shell, using the same red camera-lens shader family as
`arc_sentinel` / `shard_phantom`.

### Limbs

Each limb is a **mechanical chain**, not an octopus arm:

- one ~0.30 m dark graphite arm rod (thin cylinder, ≈0.19 m diameter),
- one ~0.31 m polished steel **ball joint** (≈0.31 m diameter) with an emissive
  role ring,
- repeated every ~0.60 m. The ball joints are the visible pivots; the rods stay
  rigid.
- no suckers, no taper, no organic skin. The last 0.06 m is a small pointed
  claw/end effector. The animated silhouettes are drawn from
  `MultiMeshInstance3D` pools (rods + balls + emissive rings).

There are **eight raised sockets** on a lower ring (52° below the equator).
Each chain leaves through the centre of its hole: the first **0.88 m of the
spine is locked to the socket axis**, then blends into the planned curve. The
first visible link therefore emerges from the recess instead of clipping over
the hole's upper lip.

### Root telescoping and length

The joint pattern is **anchored to the tip**, not the socket. When a limb
extends, the extra length appears between the socket and the first visible
joint: the chain telescopes out of the hole, and **new links appear at the
root**. Retraction is swallowed by the socket the same way; the tip-side
pattern stays intact. Compression happens **inside the body**, where it is
hidden.

The socket drum is opaque, so the stored links are invisible. There is no long
compressed root link on the outside: the visible root rod is at most one joint
spacing and it slides through the hole.

The telescoping rate, idle length, acceleration cap and minimum bend radius are
live parameters (`telescope rate`, `idle length`, `joint accel cap`,
`min bend radius`).

### Role behaviour

At any instant the boss enforces the configured caps (default **≤ 2 attacks**,
**≤ 5 supports**), and the rest are idle.

- **support floor**: while at least **3 limbs** are alive, the boss keeps **at
  least 3 supports**. If a support is cut or re-tasked, idle limbs are converted
  to support immediately.
- **idle** (15 m): the tips stay below the socket ring and flow outward, with a
  large vertical wave and a lateral travelling S. Sockets are 45° apart and
  idle/support limbs are hard-clamped to their own vertical sector, so adjacent
  limbs cannot cross near the base.
- **support** (8.9–10.1 m): a foot is planted in the limb's own sector; the body
  can drift on a 1.2 m circle while the solver changes the bow. QA: **0.000 m**
  foot slip, **2.64 %** length variation, **1.56 m** minimum bend.
- **attack 1**: the end is **pre-aimed** along the frozen start-tip→target line
  (last-segment dot **0.990–0.996**), then it accelerates from rest, passes
  **through** the target and decelerates over a configurable overshoot (2.2 m).
- **attack 2**: the tip arcs to **5.5 m above** the target, holds with the end
  pointing **straight down** (down dot **1.000**), then accelerates down through
  the chest and decelerates below it.
- **attack 3**: the limb runs out to **20 m**, lays its **entire distal band at
  1.0 m** above the floor, and performs a **full 360°** horizontal sweep around
  the body; the side of the chain does the cutting. It is independent of the
  other legs (no ducking, no retasking). QA: **357.8°**, tip radius **21.4 m**,
  band height deviation **≤ 0.015 m**.
- **laser**: only in phase 2 with the shell fully open. 0.95 s charge, 0.72 s
  fire, aimed through the core at the target.

### Cutting a limb

`CUT LIMB` severs the chosen chain **at the tip and burns back to the socket**.
The dying limb **thrashes violently** while the break travels through it:

- a **volumetric fireball** every 0.04–0.09 s of travel: a 1:1 port of Duke's
  Shadertoy *"Volumetric explosion"* (`shadertoy.com/view/lsySzd`, CC BY-NC-SA
  3.0) with its original 256×256 RGBA noise and 64×64 grey noise channels,
  random radius 0.6–2.1 m, random 2.1–3.0 s life and random 3D orientation;
- white-hot spark streaks and tumbling steel shards at the break point;
- the chain disappears link by link, then the limb is gone.

The fireballs are alpha-blended by their own accumulated optical depth, recycled
from a 72-slot pool and faded out over the last 30 % of their life. Nothing is
left hanging in the air after the limb (or the boss) moves away.

When **fewer than 3 limbs** remain, the sphere **falls to the floor**
(2.22 m centre) and **every remaining limb attacks** continuously. There is no
longer a "can't cut below 3" rule: cut as many as you like.

### Dynamics

Every limb is a 40-point spine with:

- a curvature cap (`min bend radius`, default 1.40 m) applied to the target
  curve;
- a per-point acceleration cap (`joint accel cap`, default 110 m/s²) on the
  spring-driven spine;
- a stable FABRIK length pass with base/tip pinned (support lengths stay fixed
  through role changes and body motion);
- attack/ground/body/sector projections, a socket throat and a lateral bow;
- attack 3 is driven directly (scripted sweep) so its distal band stays exactly
  flat at the configured height.

---

## Acceptance

Run `godot --headless --path . res://scenes/qa.tscn`. It steps the simulation at
a fixed 60 Hz with a fixed seed (261218) and measures the actual spines, not the
rendered images:

| check | result |
| --- | --- |
| socket exit (first segment angle) | **0.0°** from the socket axis |
| idle: mutual / self clearance | **+0.706 m / +0.582 m** |
| idle: body / ground clearance | **+0.255 m / +0.058 m** |
| idle: large waving | **3.11 m** 3D tip range, ≤3.9 m/s |
| support: mutual / self / ground | **+1.051 m / +0.781 m / +0.070 m** |
| support: foot pin / constant length | **0.000 m slip / 2.64 %** |
| support: bent, not a strut | **1.56 m** minimum chord deviation |
| attack 1: straight, pre-aimed, hit | 0.000 m line dev · dot **0.990+** · **0.17–0.24 m** |
| attack 2: over, down, hit | **5.5 m** above · dot **1.000** · **0.256 m** |
| attack 3: full sweep, flat band | **357.8°** at **21.4 m** · height dev **≤0.015 m** |
| scheduler | max 2 attacks / 5 support, **0** violations |
| support floor | 3 support / 3 idle after cutting two supports |
| fallen | body **5.96 → 2.22 m**, **2/2** remaining limbs attack |
| cut | tip→root over 14.8 m, **0** active bursts afterwards |
| phase 2 at 3 limbs | shell 0.30 → **1.00**, aperture 36.3° → **100°** |
| laser | **13.6 m**, endpoint within 0.35 m of the target |
| performance | **8.2 ms** per 60 Hz sim step (CPU, no render) |

The full JSON is in `renders/qa_report.json`.

### Visual acceptance

Visual acceptance is done by **running the main program** (`./run.sh` or
`godot --path . res://scenes/studio.tscn`) and using the limb/phase controls.
No image pile is generated or shipped with this build.

---

## Files

```text
boss/
  project.godot · run.sh
  scenes/             studio (main), character, qa, shots, probe, debug_probe
  scripts/
    boss/
      boss.gd         contract, scheduler, support floor, phases, laser, cut FX
      boss_rig.gd     shell, iris + guide ring, sockets, gimbal eye, core, glass
      tentacle.gd     per-limb planner, curvature/accel solver, socket throat,
                      telescoping chain, cut-back animation
      boss_materials.gd
    boss_stage.gd     arena, lights, environment
    target_dummy.gd   the small cyan scout target
    boss_studio.gd    camera, panel, controls, overlays
    qa.gd             61-check headless acceptance suite
    shots.gd          deterministic sequences
    probe.gd / debug_probe.gd   development probes
  shaders/            procedural metal, lens, shell glass, plasma core/orb,
                      laser, floor, screen grade, trail, 3D fire/smoke shells
  renders/
    qa_report.json    61/61 PASS
  README.md / DESIGN.md
```

---

## Honest limitations

- The limb is a spline dressed with rigid rods and ball joints. The ball joints
  are visually the pivots; this is not a physical 3-DOF rigid-body chain. The
  acceleration cap applies to the spine points, not literal joint torque limits.
- The curvature cap is a target-curve/point-space constraint; extreme user
  parameter combinations can still look tight or coil near the body.
- The iris blades slide under the rear shell; their visible phase-2 collar is the
  guide ring + rear armour.
- The containment wall is additive, not refractive glass.
- Attack 3 is a scripted 360° sweep at 1 m with a 20 m limb; the arena plate is
  23 m radius so the sweep stays inside the lit floor.
- The support floor and fallen rules are fight rules; the UI's manual role
  buttons can still put an individual limb into idle/support for inspection.
- The cut fire is Duke's Shadertoy "Volumetric explosion" (CC BY-NC-SA 3.0)
  ported 1:1 with its original iChannel0/iChannel2 noise textures; each burst is
  an 86-step raymarch, not a fluid simulation.
- This is a stylized procedural game asset, not a 3A film asset.