# Neon Reach — procedural cyberpunk city

A pure-procedural 10 km² cyberpunk city in Godot 4.7.2. No external
assets: every mesh is generated at runtime from parameters; every
surface is shader math.

## Scale & plan

- World: `x∈[−2000,2000]`, `z∈[−1250,1250]` — 4 km × 2.5 km.
- **Roads**: a warped orthogonal block grid (190 m superblocks) plus
  two diagonal avenues (`diag_a` SW→NE, `diag_b` harbour→schools), a
  dredged canal across the north, and minor streets on every block
  edge. Block interiors split into 2–10 sub-lots; 1142 buildings
  total.
- **Zones** (`src/city.gd: zone_at`): CBD spine along diag_a,
  industrial north of the canal, schools SE, residential SW,
  park cells scattered by hash.

## Buildings

Each lot extrudes a podium + slim tower shaft (`src/buildings.gd`).
Massing is per-zone: CBD towers 18–58 floors × 3.3 m, residential
2–8 floors, schools get a classroom bar + gymnasium box, industry
low sheds. Walls and curtain-wall glass are two MultiMeshes
(instanced boxes) so 1142 buildings cost ~6 draw calls.

Facades are shader math (`gfx/facade.gdshader`): a metric window
grid (~2.6 m panes + mullions + transom), per-pane lit/dark hashing
with warm/cool variance, a neon retail band on the lowest floor,
grime streaks. Glass (`gfx/glass.gdshader`) fakes interior parallax:
floor slab + furniture silhouette + per-room lit state, so windows
don't read as stickers up close.

## Landmarks (`src/landmarks.gd`)

- **Twist tower** — 190 m, 44 real floors rotated 0.55°/m for a
  105° corkscrew; magenta crown blade.
- **Cooling tower** — true hyperboloid of one sheet,
  `r(z)=r_w·cosh((z−z_w)/a)`; waist pinches, lip flares.
- **Ferris wheel** — 42 m rim torus + 24 spokes + 16 cabins + A-frame.
- **Sky rail** — elevated guideway over diag_a, glowing maglev
  beam + pylons + a lit train capsule.
- **Cable-stayed bridge** — fan cables from a 78 m pylon to a
  190 m deck across the canal.

## Interior

Two cutaway rooms at real scale (`src/interior.gd`): a CBD loft
(desk bay, shelving, lounge) and a walk-up apartment (galley
kitchen, bed nook, living end, entry onto a lit stair landing).
Each sits inside an opaque host shell so the floor-plate
relationship is visible.

## Known limitations

- Window panes merge to texture-noise at very long range.
- Interiors are two fixed rooms, not per-building — a full interior
  system is future work.
- The rail/bridge decks are structural only (no traffic sim).
- No pedestrians/vehicles yet; lamps and the retail band carry the
  street life.

## Run

```
godot --path .                       # interactive (flycam TBD)
godot --path . -- --shot=all         # renders shots/*.png, exits
godot --path . -- --shot=street,twist
```
