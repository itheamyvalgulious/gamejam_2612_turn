shader_type spatial;
render_mode cull_back;

// Facade walls: concrete/panel base + window openings punched by UV grid.
// CUSTOM0 = (seed, floor_count, zone, 0) per instance.

varying vec3 wpos;
varying vec3 wnorm;
varying vec2 fuv;
varying vec4 custom;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	fuv = UV;
	custom = INSTANCE_CUSTOM;
}

float h21(vec2 p) {
	// cell ids are large (world metres / cell size). Scaling by huge
	// constants first overflows mediump precision into speckle; fold
	// the id into a small range before hashing instead
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	float seed = custom.r * 997.0;
	float floors = max(custom.g, 1.0);
	float zone = custom.b;

	// window grid in METRES: columns ~2.6 m apart along the face's
	// horizontal axis, one row per storey — density survives scaling
	vec3 an = abs(wnorm);
	float across = (an.x > an.z) ? wpos.z : wpos.x;
	// wider bays: a 2.6 m module shrinks to a few pixels within metres
	// and reads as grain; ~4.5 m curtain bays stay legible up close
	float col_w = 6.0 + h21(vec2(seed, 3.0)) * 2.0;
	// vertical axis is world height — one cell per storey. fuv/UV
	// proved unreliable on these instances (all zeros), and world-Y
	// gives true storey bands at any scale anyway
	float storey = 3.3;
	vec2 cell = vec2(across / col_w, wpos.y / storey);
	vec2 cf = fract(cell);
	vec2 ci = floor(cell);

	// fragment footprint in cells — when a window cell shrinks toward
	// one pixel the pane/mullion pattern moirés into speckle noise.
	// lod fades the whole grid to its average once cells go sub-pixel
	// distance-only fade: fwidth itself is per-pixel and its jitter was
	// the speckle — drop it entirely. The window grid's cells shrink
	// past readability beyond ~400 m and inside ~150 m they are always
	// pixel-scale, so camera distance alone is a clean, stable fade
	float dcam = distance(CAMERA_POSITION_WORLD, wpos);
	// window grid is a CLOSE-RANGE detail only — past ~90 m each bay
	// is a handful of pixels and reads as grain no matter the shading
	float dist_lod = 1.0 - smoothstep(12.0, 28.0, dcam);
	// screen-space cell size: under ~10 px per bay the grid can't be
	// sampled and moirés into the concentric banding on every face —
	// footprint decides, not just distance
	float px = 1.0 / max(fwidth(cell.x), fwidth(cell.y));
	float cell_lod = smoothstep(18.0, 32.0, px);
	// grazing faces compress the across axis to sub-pixel cells — the
	// pattern undersamples into speckle no matter how the lod fades.
	// Below ~35° the face degrades to flat wall: no grid, no streaks,
	// just material colour
	vec3 vd = normalize(CAMERA_POSITION_WORLD - wpos);
	float grazing = step(0.62, abs(dot(vd, wnorm)));
	float lod = dist_lod * grazing * cell_lod;
	// hard cut: a partial lod still draws a sub-pixel grid that aliases
	// into grain. Below the halfway point the pattern simply doesn't
	// exist — the wall is a clean material surface
	lod = step(0.85, lod) * lod;

	// far LOD: don't kill the grid — collapse it. Past the fade the
	// cell jumps 4× coarser so distant towers keep a readable band
	// of glazing instead of going blank plaster
	vec2 cell_far = cell * 0.25;
	vec2 cf_far = fract(cell_far);
	vec2 ci_far = floor(cell_far);
	vec2 cfx = mix(cf_far, cf, lod);
	vec2 cix = mix(ci_far, ci, lod);
	cf = cfx; ci = cix;

	// window aperture with fwidth-softened edges — hard step() edges
	// speckle at every grazing angle; the footprint derivative gives
	// each edge a ~1 px transition band instead. Measure the CELL, not
	// cf — fwidth of fract() explodes at cell boundaries and was the
	// concentric moiré banding
	vec2 fw = max(fwidth(cell) * 0.5, vec2(0.001));
	float wx = smoothstep(0.22 - fw.x, 0.22 + fw.x, cf.x) *
		smoothstep(0.78 + fw.x, 0.78 - fw.x, cf.x);
	float wy = smoothstep(0.30 - fw.y, 0.30 + fw.y, cf.y) *
		smoothstep(0.70 + fw.y, 0.70 - fw.y, cf.y);
	float win = wx * wy * step(abs(wnorm.y), 0.45);
	// lit regions are WHOLE FLOOR BANDS + occasional column groups —
	// per-pane random lit windows scatter into speckle noise as soon
	// as the cell drops below a few pixels. Banding keeps the night
	// tenancy readable at every distance
	// lit floors only — keyed to the storey id alone. Any per-column
	// term (grp) breaks into scattered grains the moment the face
	// slants and ci.x sweeps several cells per pixel
	float band = h21(vec2(ci.y, seed * 0.31));
	// lit bands only exist on vertical walls — on sloped caps and
	// podiums the world-Y cell sweeps storeys across the face and the
	// threshold scatters into a grain field
	float lit = step(0.94, band) * step(abs(wnorm.y), 0.45);
	float floor_dark = step(0.18, h21(vec2(ci.y, seed * 0.7)));
	// lit bands wash the whole storey — the window grid never enters
	// the emission, so a lit floor is a clean horizontal band at any
	// angle or distance
	float litwin = lit * floor_dark;
	// a lit storey is a CONTINUOUS band — the window grid's dark panes
	// inside a lit floor shred the band into scattered dots at range,
	// so lit floors drop the aperture pattern entirely
	win *= 1.0 - litwin;
	// distant LOD: the speckle dies, but a faint average tenancy glow
	// survives so far towers still read as occupied mass, not black
	float avg_glow = (1.0 - lod) * 0.0; // coarse far-grid carries it
	// warm/cool variance per pane — sodium, tungsten dominate; cool
	// office-white is rare so towers don't read as LED screens
	// lit colour varies per floor band (not per pane) so a lit storey
	// reads as one warm wash, not a scatter of hues
	float warm = h21(vec2(ci.y, seed * 0.13));
	vec3 litcol = warm < 0.72 ? vec3(1.0, 0.62, 0.28) :
		(warm < 0.92 ? vec3(0.95, 0.78, 0.50) : vec3(0.62, 0.72, 0.95));
	// ground-floor retail band: the lowest floor of each podium glows —
	// shopfronts carry the street's neon wash
	// retail band: the first two storeys of the podium face the street
	// retail band: a continuous shopfront wash, not per-pane cells —
	// per-pane neon was the speckled strip along the podium base
	float retail = 0.0; // DIAG
	vec3 neon = mix(vec3(1.0, 0.42, 0.35), vec3(0.35, 0.75, 0.9),
		step(0.5, h21(vec2(floor(across / 24.0), seed * 0.23))));

	// facade material: concrete panels with a panel groove every 2 floors
	vec3 base = COLOR.rgb;
	float groove = smoothstep(0.94, 1.0, abs(fract(wpos.y / 6.6) * 2.0 - 1.0));
	base *= 1.0 - groove * 0.12;
	// grime streaks quantized per ~1.5 m column — the across axis sweeps
	// through many streaks per pixel at grazing angles, so the streak
	// pattern itself is what became the speckled grain. Fade it with
	// the same lod as the window grid
	float grime = h21(vec2(floor(across / (col_w * 0.5)) + seed, 0.0));
	base *= 1.0 - grime * 0.18 * lod;
	// grazing faces also lose the AO gradient detail — flat material
	base = mix(base, COLOR.rgb * 0.92, 1.0 - grazing);
	// vertical AO gradient — bases sit in street shadow, tops catch
	// sky; gives the shaft a vertical component at any distance
	base *= 0.82 + 0.18 * clamp(wpos.y / 60.0, 0.0, 1.0);

	// dark glass inside apertures — subtle darkening only, so a face
	// keeps its material reading where the grid survives
	ALBEDO = mix(base, base * 0.55, win * 0.6);
	ROUGHNESS = 0.9;
	// lit interiors glow at night — per-pane brightness so a lit room
	// reads as a room, not a floodlight; the retail band runs hot neon
	// one brightness per lit storey band — per-pane brightness jitter
	// inside a lit band was the granular speckle on tower faces
	float bright = 0.30 + 0.55 * h21(vec2(ci.y, seed * 0.41));
	EMISSION = litcol * litwin * bright * 0.30
		+ neon * retail * 0.7
		+ vec3(1.0, 0.72, 0.42) * avg_glow;
}
