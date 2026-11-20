# ARC // SENTINEL v2 — implementation & validation record

This file records how the delivered project maps to the redesign brief and how
the claims were checked. It is intentionally separate from the art/usage README.

## 1. Brief → implementation

| requirement | implementation |
| --- | --- |
| complete remodel as a two-wheel balancer | new `ArcRig2` skeleton/geometry: solid treaded wheels, independent swing-arm + coil-over suspension, small cylindrical hull, front camera pod, rear bulge + shield hook, left sheath, two 3-ball-joint arms |
| no head | no head node/geometry; the only "face" is the front camera objective |
| solid wheels, no spokes, metal tread ring | `MK.disc` solid wheel + 18 raised beveled tread plates per wheel, steel ridges and hub rings |
| independent suspension | axles are children of the rig root (stay on the ground); body-mounted swing arm and spring are stretched to the axle every pose |
| black + orange-red metal | near-black metal palette + orange-red inserts/seams/iris; procedural metal shader + SSR/reflection probe |
| sword from `weapon_electricity_sword`, no hilt, short generator head on the hand | ported `ArcField2`/`ArcBolt2`/`ArcSwordFX2` and the ribbon shader; a 0.13 m generator head is the last right-arm segment |
| shield style kept | same hard-light disc/struts/rim construction, recolored orange-red to the palette |
| rest: sword sheathed, shield on back, hands low | `rest` clip: right tool docks at the left sheath mouth (blade off), left tool docks on the rear hook (shield on the back), torso twisted 35°, low folded arms |
| draw / sheathe transitions | `draw` and `sheathe` one-shots with Cartesian shield/sword paths around the left side; blade ignites only after clearing the sheath and turns off before re-entry |
| two attacks with authored elbow paths | Fixed-length links follow elbow and wrist guides, with timed body weight shifts and suspension rebound |
| left 45° must be shield; right 45° sword; no guard | `defend` resolves by threat; QA ray/disc and ray/segment tests: miss 0.000 m, effector shield/sword, no `guard` string |
| actions connect without clipping | one-shots are never cancelled; rest↔drawn via draw/sheathe; reachable transition blends audited ≥ +0.0501 m |
| 0 collisions between unconnected parts | capsule/disc proxy audit on every clip frame, every reachable transition and both block poses; all clearances positive; QA PASS |
| solver <50 ms, ideally <20 ms, table ≤50 MB | analytic IK + collision-aware swivel + quaternion joints; trajectories baked to `data/arc_traj_v2.json` (~0.72 MB); runtime attack/attack_up 1 ms, block ≤13 ms |
| metal not plastic | procedural PBR metal shader (brushed micro-grooves, roughness breakup, pitting, sparse scratches, fresnel edge wear); material tuning by closeup review; SSR/reflection probe |
| vision subagent reviews all motion frames | final vision reviewer reads the 9 contact sheets (all 16 frames × 4 views) and individual full-res frames; report in `renders/v2/VISION_REVIEW.md` |

## 2. Solver

1. **Analytic arm IK**: shoulder + elbow as a 2-bone chain; the free swivel
   angle around the shoulder→wrist axis is sampled, ranked by joint-limit cost,
   body clearance and (for trajectory samples) continuity. The wrist is a
   3-DOF ball; the elbow can also share the forearm twist if it reduces the
   wrist excursion. All joint orientations are stored as quaternions.
2. **Collision proxies**: capsules for the hull/camera/links/blade, discs for
   the shield/wheels/chassis, spheres for the ball joints. Adjacent chain links
   are exempt; docked generator/sheath and shield/rear-hook pairs are exempt
   only while actually docked. All other pairs are checked.
3. **Attacks** use explicit elbow and wrist guides and preserve both upper
   and lower link lengths. The blade face is transported along the arc and
   returns to the guard orientation during recovery.
4. **Other actions** use Cartesian tool targets, a warm-start swivel, and
   collision-aware trajectory sampling.
5. **Table**: the final per-clip joint trajectories and key poses are baked to
   `data/arc_traj_v2.json`. The table is signed by the live geometry parameters
   and the authored strike revision. A mismatch falls back to the runtime
   motion builder. Size ≈0.72 MB, well under 50 MB.

## 3. Model / runtime fixes in this revision

* **Suspension** is a telescopic rod between the chassis and the inboard hub
  carrier, with the coil spring sleeved directly on it. The whole strut is
  stretched between its mounts, so rod, sleeve and spring extend together; no
  swing arm crosses the wheel face.
* **Camera** is a small ball eye just outside the hull (ball r 0.115, barrel
  r 0.092). Only a 0.08 m barrel/pod retraction is allowed; the glowing lens
  remains the outermost part. Yaw/pitch rotate the ball itself, the static
  iris/socket closes the hull behind it, and the barrel keeps its forward aim
  through the attack poses.
* **Hull shell** loft winding was clockwise-corrected, so the cylinder side
  wall, back and bottom caps are solid instead of showing the far inner wall.
* **Wheels** have a glowing ring on the outboard face; tire/tread albedo was
  lifted slightly so the wheel no longer reads as a black disc.
* **Ambient** is adjustable in the studio PARAMS panel (`ENVIRONMENT`:
  ambient light 1.25, exposure 1.15 defaults) and drives the WorldEnvironment.
* **Runtime stutter** came from a 0.6 s `measure_radius()` full-vertex scan and
  a 0.25 s collision sweep. Both are gone: radius is measured once per build,
  clearance once per clip change. The additive blade-core plane was deleted, so
  a long frame cannot reveal a translucent sword.
* **State machine** now tracks a logical rest/drawn stance; every request ends
  in a loop, draw/sheathe are never skipped due to a stale `current_anim`, and
  requests during a one-shot resolve to the latest target.

## 4. Validation

`godot --headless --path . res://scenes/qa.tscn` → PASS (0 failures). The
machine-readable report is `renders/v2/qa_report.json`.

* Every clip is sampled at 97 points; non-adjacent proxy clearance is positive:
  rest +0.0265, idle +0.0526, walk +0.0407, attack +0.0091, attack_up +0.0080,
  defend +0.0130, draw +0.0265, sheathe +0.0536 m; floor ≥ 0.
* All state-machine-reachable crossfades (idle/walk and one-shot ends into any
  drawn state) audited; worst +0.0501 m. Direct rest↔drawn blends are negative
  by design and are never executed (the state machine routes them through
  draw/sheathe).
* Attacks are checked for direction, elbow flexion, clearance and forward aim.
* Blocks: left 45° shield miss 0.000 m, clearance +0.0130 m; right 45° sword
  miss 0.000 m, clearance +0.0191 m.
* Runtime plan: attack 1 ms, attack_up 1 ms, block ≤13 ms; build with table
  load ~50 ms; offline bake ~30 s.

## 5. Visual validation

`renders/v2/sheets/*.png` contain every motion frame (16 frames × 4 views per
clip). The final independent vision review is in
`renders/v2/VISION_REVIEW.md`. Metal/camera/wheel/shield/sword closeups are in
`renders/v2/details/`; the mandated block renders are
`renders/v2/block_left.png` and `block_right.png`.

The new strike guides route the arm around the camera at its deployed
position while the optic compensates for movement of the chassis.

## 6. Agent usage

* `metal-shader` (dawnfm/deepseek-v4.1-flash-1017, max): original procedural
  metal shader; later reviewed/tuned in the main session.
* `blade-port` (same model): ported the electric arc field/bolt/ribbon from
  `weapon_electricity_sword`, adding a configurable blade scale; verified the
  tip length exactly.
* Vision capability test + independent motion review + final vision review
  (vision-capable subagents): see `renders/v2/VISION_REVIEW.md`.
* All implementation, solver integration, collision audit and fixes were done
  in the main session with the QA harness.

## 7. References / techniques consulted

* Korein & Badler, "Techniques for Generating the Goal-Directed Motion of
  Articulated Structures", IEEE CG&A 1982 — analytic 2-bone/swivel IK.
* Tolani, Goswami & Badler, "Real-Time Inverse Kinematics Techniques for
  Anthropomorphic Limbs", Graphical Models 2000.
* Wampler, "Manipulator Inverse Kinematic Solutions Based on Vector
  Formulations and Damped Least-Squares Methods", IEEE SMC 1986.
* Aristidou & Lasenby, "FABRIK: A fast, iterative solver for the Inverse
  Kinematics problem", Graphical Models 2011.
* LaValle, "Rapidly-Exploring Random Trees: A New Tool for Path Planning",
  TR 98-11, 1998; Kuffner & LaValle, RRT-Connect, ICRA 2000.
* Ratliff et al., "CHOMP: Gradient Optimization Techniques for Efficient Motion
  Planning", ICRA 2009; Kalakrishnan et al., "STOMP: Stochastic Trajectory
  Optimization for Motion Planning", ICRA 2011.
* Lightning-leader model references are in `scripts/ch/arc_field.gd`
  (Niemeyer/Pietronero/Wiesmann 1984; leader/branching papers 2008–2023).