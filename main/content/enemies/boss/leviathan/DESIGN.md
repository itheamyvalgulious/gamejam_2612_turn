# LEVIATHAN — design / implementation notes

This document explains *why* the boss is built this way, the math behind the
limbs and the shell, and what the acceptance suite actually measures.

---

## 1. Scale and silhouette

A mechanical octopus, not a biological one: a 2 m-radius sphere and eight
uniform, thin, long jointed chains.

| quantity | value |
| --- | --- |
| body radius | **2.00 m** (4.0 m diameter) |
| body centre, supported | **6.00 m** |
| body centre, resting | **2.06 m** (sphere touches the floor) |
| socket ring | 52° below the equator, 8 sockets 45° apart |
| limb joints | 0.30 m rod + ≈0.31 m ball, repeating every 0.60 m |
| rod / ball diameter | 0.19 m / 0.31 m |
| idle limb length | **15.0 m** |
| support limb length | **8.9–10.1 m** (planted) |
| attack 3 length | **20.0 m** |
| phase-1 aperture | 36.3° half-angle |
| phase-2 aperture | 100° half-angle |

The visual rule is *one arm segment, one ball joint, repeating*. Three
`MultiMeshInstance3D` pools per limb (rods, balls, emissive rings) draw the
whole chain; the last 6 cm is a pointed claw. The sockets are raised drums
with a dark recess and a glowing rim.

The body carries a fixed rear armour shell, an inner liner, eight iris blades
that slide under the armour, a continuous aperture guide ring, a gimballed
camera eye, and a phase-2 plasma core inside an additive containment wall.

---

## 2. Limb architecture

Each limb has its own state machine and planner; no animation tracks. The limb
is a **40-point world-space spine**, solved every frame.

### 2.1 Modes

- `idle`: the tip rides an arc around the socket, below the socket ring. A large
  vertical wave (`swing` −0.28…0.26 rad) plus a faster secondary component; the
  excess length is spent as a **lateral S**, not a vertical arch, so the chain
  leaves the hole flowing down and outward.
- `support`: a foot is chosen in the limb's own vertical sector at 6.2–7.5 m
  from the body centre, lifted into a Bézier transition, then **pinned**. The
  target length is fixed at plant time = chord + 2.4 m, clamped 7–13 m.
- `attack`: one-shot timeline, see §2.4.
- `explode`: a cut limb is clipped at a receding cut point from tip to root,
  with a joint pop at every ball joint; then it is removed.

Idle↔support transitions use a quadratic Bézier tip path with a lift (0.95 s).

### 2.2 Curve construction

For a base `B`, tip `T`, socket direction `u`, length `L`, tip approach `a` and
bow direction `b`:

1. `m0 = normalize(0.75 u + 0.25 u_h) · clamp(0.30 L, 0.9, 3.2)`
2. `m1 = normalize(a) · clamp(0.24 L, 0.7, 2.8)`
3. a cubic Hermite `H(t)` through `B, m0, T, m1`;
4. a perpendicular bow `b⊥ · bow · sin(πt)^0.92`;
5. two travelling waves perpendicular to the chord with amplitudes decaying at
   both ends; `wave_amp` is 0.60 for idle, 0.12 for support, near zero in
   attacks;
6. the bow magnitude is **solved** by bisection so the arc length matches `L`.

The sampled curve is resampled to 40 equal-arc points, then:

- **socket throat**: the first 0.88 m is replaced by points on the socket axis,
  and the next 0.87 m blends back into the curve. This is what guarantees the
  chain leaves through the centre of the hole instead of clipping its upper lip
  (QA measures **0.0°** first-segment deviation). The same constraint is
  re-applied after the dynamics pass.
- projected out of the body sphere (`2.035 + radius + 0.02`) and above the
  floor (`radius + 0.075`);
- clamped to the limb's vertical sector for idle/support;
- re-pinned at base and tip.

### 2.3 Joints, telescoping and compression

The visible joint pattern is **tip-anchored**: joints are placed every 0.60 m
backwards from the tip. The root gap is therefore whatever length is left
between the socket and the first visible joint (≤ one spacing). As the limb
extends, new length is inserted **at the socket**; as it retracts, links are
pulled into the socket drum and hidden inside the body. There is no compressed
or stretched “super link” outside the hole.

The two `MultiMesh` pools are sized for the 15–20 m range (40 links).

### 2.4 Curve dynamics

The target curve is driven by a spring on every interior spine point with

```
a = (target − p)·k² − v·2k,   |a| ≤ max_accel
```

with `k = 10`, `max_accel = 110 m/s²` by default. A FABRIK pass with base and
tip pinned restores the rest lengths, then the body/floor/sector projections run
again. A finite/≤80 m sanity check re-seeds the spring if a pathological
parameter set destabilises it.

The curvature cap is enforced in point space: for each triple `(a, b, c)` the
circumradius is estimated from the chord and sagitta; if `R < bend_radius`
(default 1.40 m) the middle point is pulled toward the chord midpoint.

Attack 3 is the exception: its 360° sweep is **scripted directly** (no spring
lag), because the whole distal band has to stay at exactly 1.0 m while it
rotates.

### 2.5 Why idle/support limbs cannot intersect

Each limb owns a vertical sector of its socket (45° apart). Idle/support
spines are hard-clamped to ±0.26 rad around their sector axis; the shared axis
of adjacent sectors is the vertical line through the body, and every point is
outside the body radius. A final point-pair relaxation pass with a 0.14–0.16 m
margin is only a safety net. QA: idle mutual clearance **+0.706 m**, support
**+1.051 m**.

---

## 3. Attacks

| kind | duration | key frames | length target |
| --- | --- | --- | --- |
| 1 | 2.5–3.2 s | orient 0–0.62, accelerate 0.62–(0.62+t1), overshoot t2, recover | chord + overshoot + 2.2 m |
| 2 | 3.4–4.2 s | arc 0–0.90, hold 0.90–1.20, plunge 1.20–1.46, overshoot, recover | max(overhead, target) + 2 m |
| 3 | 6.45 s | lower 0–0.95, settle 0.95–1.75, **360° sweep 1.75–5.35**, recover | **20 m** |

- **Attack 1** freezes the line at the current tip→target. The first 0.62 s only
  rotates the end of the limb onto that line; then the tip follows a
  trapezoidal speed profile (accelerate from rest, pass through, decelerate over
  the overshoot). The last two links are forced straight along the strike
  direction, so the hit is a point-first stab. QA pre-aim dot **0.990–0.996**,
  closest sample **0.17–0.24 m**.
- **Attack 2** uses a Bézier to 5.5 m above the target, holds with the end
  pointing down (dot **1.000**), then a trapezoidal vertical plunge through the
  chest and a deceleration below it. QA closest sample **0.256 m**.
- **Attack 3** builds a dedicated **low band** path: from the socket, a cubic
  descent to a knee at 1.0 m just outside the root, then a straight radial run
  to the tip. The tip radius is solved from the 20 m length (≈21.4 m). The whole
  band then rotates 360° about the body. No other limb changes role or ducks.
  QA: **357.8°**, band height deviation **≤0.015 m** from r = 4.2 m outward.

---

## 4. Roles, support floor and the fallen state

Every 2 s (auto roles), two eligible limbs are re-tasked with weighted
probabilities, subject to caps: attacks ≤ 2, supports ≤ 5.

Two rules are stronger than the scheduler:

1. **Support floor.** While `live ≥ 3`, at least **3** supports are kept. Any
   support that is cut or re-tasked is replaced immediately by an idle limb.
   A support at the floor is never chosen for an attack/idle re-task.
2. **Fallen.** When `live < 3`, the boss drops all supports, the body falls to
   `2.06 m`, and **every remaining live limb attacks** continuously until it is
   cut. This rule applies in manual/QA mode too.

The body height is

```
H = 2.06 + (6.00 − 2.06) · clamp(supports / 3, 0, 1)
```

rate-limited at 0.62 m/s (1.35 m/s when falling), with a 1.2 m Lissajous/circle
drift. Each support foot is pinned in world space; the solver changes the bow
to keep the planted arc length. QA: **0.000 m** slip, **2.64 %** worst length
variation, **1.56 m** minimum bend.

---

## 5. Cutting and the explosion

`cut_tentacle()` starts a `role = "explode"` state and decrements `live`
immediately. The remaining chain is **whipped around the socket** while the
break travels through it: a seeded yaw plus two high-frequency lateral waves
(f scaled by arclength) give a violent mechanical flail, re-projected out of the
body and floor. The visible chain is clipped at `explode_cut`, which moves from
`total` to 0 over

```
T = clamp(total · 0.120, 1.05, 2.80) s
```

The fire is Duke's **"Volumetric explosion"** (`shadertoy.com/view/lsySzd`,
CC BY-NC-SA 3.0), ported 1:1: the same `BOTH` split, `DITHERING` step, spiral
noise, ray-sphere intersection, density accumulation and colour curve, with the
original iChannel0 (RGBA noise medium, 256×256) and iChannel2 (grey noise small,
64×64) textures shipped under `shaders/`.

Two details decide whether the port looks like the reference:

- the inner `float d = map(pos);` **shadows** the outer `d`, so the
  `d < 0.12*t` early-out never fires and the volume actually fills up;
- `#define TONEMAPPING` is off, so the demo writes display-space values. The 3D
  pipeline is ACES-tonemapped, so the shader applies the inverse sRGB curve
  before adding the fireball to the scene.

Every 0.04–0.09 s of cut travel a fireball is spawned at the receding break
point: random radius 0.6–2.1 m, random 2.1–3.0 s lifetime, random 2.4–3.7×
playback speed and a random 3D orientation of the noise field; the 72-slot pool
recycles the oldest. Bursts are **alpha-blended by their own accumulated optical
depth** (`sum.a`) instead of added, so the dense core occludes the arena and the
internal cavities read as depth instead of washing out to white. Each burst
fades in over the first 8 % of its life and out over the last 30 % (a 0.6–0.9 s
tail). Playback is clamped at 8.5 s so a burst cannot wrap back into ignition;
the whole trail lingers and burns out instead of popping off while the cut is
still travelling. 14 spark streaks, 6 tumbling shards and a point light
ride on the break point. When `explode_cut` reaches 0 the limb sets
`role = "dead"`, stops spawning, and hides its root forever. QA verifies that the
cut starts at the tip, decreases monotonically, and that **0** bursts remain
after the animation, even if the body has moved away.

---

## 6. Phases and laser

`phase = 2` if `live ≤ 3` or the UI forces it. The shell opens from 0.30 to 1.00
at 0.22/s; the core transforms at 0.65/s. Phase-2 entry spawns a shock ring. At
`shell_t > 0.90` and `phase2_t > 0.5` the laser is armed; auto fire every 6.2 s,
or `fire_laser()`.

Laser: charge 0.95 s, fire 0.72 s (two additive cylinders from the core toward
the target, plus a muzzle quad and an impact), cool 0.55 s. QA verifies the beam
endpoint is within 0.35 m of the target (13.6 m measured).

---

## 7. Rendering and acceptance

- Forward+, MSAA 4×, ACES, glow, SSR, SSAO, volumetric fog (low density).
- Procedural metal shaders (object-space triplanar noise, brushed grooves, pits,
  scratches, fresnel edge wear), polar-ring arena floor, pylons, neon bars.
- Dynamic parts: 8 × 3 chain MultiMeshes, 8 tips + rings, iris blades, guide
  ring, gimbal, core, glass, beam, impact pool, cut-burst pool, trails.
- Per-frame sim cost measured by QA: **≈8.2 ms** at 60 Hz (headless, no render).

`scenes/qa.tscn` runs **61 checks** at 60 Hz with seed 261218: socket exit,
idle clearance/waving/speed, support clearance/pin/length/bend/circle, three
attacks on three targets, scheduler caps/rotation, support floor, fallen state,
cut order/residue, phase transition, laser endpoint, perf. It currently reports
**PASS / 0 failures**; the JSON is `renders/qa_report.json`.

Visual acceptance is done by running the main program directly; no image pile is
generated or shipped.

---

## 8. Known trade-offs

- The chain is a spline dressed with rigid links; it is not a physical rigid
  body chain with ball-joint constraints.
- The curvature cap is a point-space constraint; extreme parameter combinations
  can still look tight near the body.
- The iris blades hide under the rear armour; the guide ring is the visible
  phase-2 collar.
- The containment wall is additive, not refractive glass.
- The laser and impacts are visual only.
- The cut fire is an 86-step raymarch per burst, not a fluid simulation.
- Attack 3 is 20 m long at 1 m; the far tip passes beyond the lit arena plate.
- Support-length invariance is validated at 1.2 m body drift; the 2 m design
  budget has less slack.
- This is a stylized procedural game asset, not a 3A film asset.