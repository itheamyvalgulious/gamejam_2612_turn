#!/usr/bin/env python3
"""AETHER - offline procedural PBR texture baker.

All textures are periodic (seamless) and generated from noise / Voronoi /
FFT bands.  The PNGs are inputs to the shaders; no scanned assets.
Run:  python3 tools/gen_textures.py
"""
import numpy as np
from PIL import Image
import os, math

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
os.makedirs(OUT, exist_ok=True)

def norm01(a):
    a = a.astype(np.float64)
    mn, mx = a.min(), a.max()
    return (a - mn) / (mx - mn + 1e-9)

def fft_band(size, wavelength, seed, aspect=1.0, angle=0.0):
    """Periodic band-limited noise; wavelength in pixels."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((size, size))
    F = np.fft.fft2(w)
    fy, fx = np.meshgrid(np.fft.fftfreq(size), np.fft.fftfreq(size), indexing="ij")
    ca, sa = math.cos(angle), math.sin(angle)
    u = fx * ca + fy * sa
    v = -fx * sa + fy * ca
    r = np.sqrt((u * aspect) ** 2 + v ** 2)
    fc = 1.0 / max(wavelength, 1.0)
    band = np.exp(-0.5 * ((r - fc) / (0.42 * fc + 1e-6)) ** 2)
    out = np.real(np.fft.ifft2(F * band))
    return norm01(out)

def fbm(size, seed, base=512.0, octaves=7, gain=0.55):
    v = np.zeros((size, size))
    amp = 1.0
    wl = base
    for o in range(octaves):
        v += amp * (fft_band(size, wl, seed + 97 * o) * 2.0 - 1.0)
        wl = max(wl * 0.5, 2.0)
        amp *= gain
    return norm01(v)

def warp(size, seed, scale=8.0):
    a = fbm(size, seed + 517, base=max(size / scale, 8.0), octaves=4)
    return (a - 0.5) * 2.0

def sin_bands(size, cycles, seed, angle=0.0, warp_amp=0.8):
    y, x = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    u = (x * math.cos(angle) + y * math.sin(angle)) / size
    w = warp(size, seed, scale=6.0)
    s = 0.5 + 0.5 * np.sin(2.0 * np.pi * cycles * u + w * warp_amp)
    return s

def voronoi(size, cells, seed):
    """Periodic Voronoi: returns F1, F2 and per-cell random value."""
    rng = np.random.default_rng(seed)
    pts = rng.random((cells, cells, 2))
    rnd = rng.random((cells, cells))
    xs = (np.arange(size) + 0.5) / size * cells
    gx = np.floor(xs).astype(np.int64)
    fx = xs - gx
    X, Y = np.meshgrid(fx, fx, indexing="xy")  # X varies along width, Y along height
    GX, GY = np.meshgrid(gx, gx, indexing="xy")
    f1 = np.full((size, size), 9.0)
    f2 = np.full((size, size), 9.0)
    cid = np.zeros((size, size))
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx = (GX + ox) % cells
            cy = (GY + oy) % cells
            px = pts[cy, cx, 0] + ox
            py = pts[cy, cx, 1] + oy
            d = np.sqrt((px - X) ** 2 + (py - Y) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            f1 = np.where(closer, d, f1)
            cid = np.where(closer, rnd[cy, cx], cid)
    return f1, f2, cid

def normal_map(h, strength=2.0, invert_y=False):
    h = h.astype(np.float64)
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -gx * strength
    ny = (-gy if not invert_y else gy) * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1)
    return np.clip(rgb * 0.5 + 0.5, 0, 1).astype(np.float64)

def save(name, arr, mode="RGB"):
    a = np.clip(arr, 0, 1)
    if mode == "RGB":
        img = Image.fromarray((a * 255).astype(np.uint8), "RGB")
    else:
        img = Image.fromarray((a * 255).astype(np.uint8), "L")
    img.save(os.path.join(OUT, name))

def mix(a, b, t):
    t = t[..., None] if a.ndim == 3 and t.ndim == 2 else t
    return a * (1.0 - t) + b * t

def colorize(t, stops):
    """stops: list of (pos, (r,g,b)); returns HxWx3."""
    out = np.zeros(t.shape + (3,))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        m = (t >= p0) & (t <= p1)
        f = np.clip((t - p0) / (p1 - p0 + 1e-9), 0, 1)
        for k in range(3):
            out[..., k] = np.where(m, c0[k] * (1 - f) + c1[k] * f, out[..., k])
    return out

# ---------------------------------------------------------------- rock
def make_rock(size=1024):
    base = fbm(size, 11, base=512, octaves=7, gain=0.56)
    detail = fbm(size, 12, base=64, octaves=5, gain=0.55)
    strata = sin_bands(size, 9, 13, angle=np.pi * 0.5, warp_amp=1.1)
    strata2 = sin_bands(size, 23, 14, angle=np.pi * 0.5 + 0.06, warp_amp=0.6)
    # irregular fracture lines from ridged noise, not a uniform mud-crack net
    frac = fbm(size, 15, base=110, octaves=5)
    lines = np.clip(1.0 - np.abs(2.0 * frac - 1.0) / 0.10, 0, 1)
    f1, f2, cid = voronoi(size, 18, 16)
    pits = np.clip((f2 - f1) / 0.16, 0, 1)
    h = 0.50 * base + 0.22 * detail + 0.10 * strata + 0.05 * strata2
    h -= 0.035 * lines + 0.025 * (1.0 - pits)
    h += 0.05 * (cid - 0.5)
    h = norm01(h)
    alb = colorize(h, [(0.0, (0.160, 0.165, 0.170)), (0.35, (0.280, 0.275, 0.265)),
                       (0.62, (0.400, 0.385, 0.360)), (0.82, (0.520, 0.500, 0.465)),
                       (1.0, (0.680, 0.655, 0.615))])
    alb *= (0.72 + 0.42 * strata[..., None])
    # lichen / moss
    lich = norm01(fbm(size, 16, base=96, octaves=4))
    lich = np.clip((lich - 0.56) / 0.22, 0, 1) * np.clip((h - 0.5) * 4, 0, 1)
    alb = mix(alb, np.array([0.16, 0.23, 0.09]), lich * 0.55)
    # dark cracks and grit
    alb *= (0.88 + 0.12 * (1.0 - lines))[..., None]
    alb *= (0.94 + 0.06 * pits)[..., None]
    grit = fbm(size, 17, base=4, octaves=2)
    alb *= (0.85 + 0.3 * grit)[..., None]
    save("rock_albedo.png", alb)
    save("rock_normal.png", normal_map(h, 30.0))
    save("rock_height.png", h, "L")
    rough = np.clip(0.68 + 0.22 * (1 - h) + 0.1 * grit, 0, 1)
    save("rock_rough.png", rough, "L")
    return alb, h

# ---------------------------------------------------------------- snow
def make_snow(size=1024):
    w = warp(size, 21, scale=5.0)
    y, x = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    u = (x * 0.86 + y * 0.50) / size
    sas = 0.5 + 0.5 * np.sin(2 * np.pi * 11 * u + w * 2.6)
    sas = sas ** 2.2
    sas2 = 0.5 + 0.5 * np.sin(2 * np.pi * 29 * u + w * 4.0)
    fine = fbm(size, 22, base=48, octaves=5, gain=0.55)
    micro = fbm(size, 23, base=5, octaves=3)
    h = 0.52 * sas + 0.18 * sas2 + 0.18 * fine + 0.08 * micro
    h = norm01(h)
    base = np.array([0.80, 0.855, 0.93])
    alb = base[None, None, :] * (0.86 + 0.16 * h[..., None])
    trough = np.clip((0.45 - h) * 2.5, 0, 1)
    alb = mix(alb, np.array([0.58, 0.67, 0.80]), trough * 0.55)
    # sparkle: sparse bright crystals
    rng = np.random.default_rng(24)
    sp = (rng.random((size, size)) > 0.9985).astype(np.float64)
    for _ in range(2):
        sp = np.maximum(sp, np.roll(sp, 1, axis=0))
    alb = np.maximum(alb, sp[..., None] * 0.98)
    save("snow_albedo.png", alb)
    save("snow_normal.png", normal_map(h, 22.0))
    save("snow_height.png", h, "L")
    save("snow_rough.png", np.clip(0.38 + 0.25 * trough + 0.12 * fine, 0, 1), "L")

# ---------------------------------------------------------------- forest ground
def make_ground(size=1024):
    soil = fbm(size, 31, base=384, octaves=6, gain=0.55)
    fine = fbm(size, 32, base=32, octaves=5)
    f1, f2, cid = voronoi(size, 38, 33)       # pebbles / soil clods
    peb = np.clip((f2 - f1) / 0.20, 0, 1)
    pebble = (1.0 - peb) * np.clip((cid - 0.55) * 6, 0, 1)
    f1b, f2b, cidb = voronoi(size, 15, 34)    # leaf-litter patches
    litter = np.clip((cidb - 0.55) * 3.0, 0, 1) * np.clip((f2b - f1b) / 0.25, 0, 1)
    root = sin_bands(size, 6, 35, angle=0.9, warp_amp=1.8)
    root = np.clip((root - 0.72) * 4.0, 0, 1)
    h = 0.48 * soil + 0.18 * fine + 0.16 * pebble + 0.08 * litter + 0.06 * root
    h = norm01(h)
    alb = colorize(h, [(0.0, (0.060, 0.052, 0.036)), (0.3, (0.135, 0.105, 0.060)),
                       (0.6, (0.225, 0.175, 0.095)), (0.85, (0.330, 0.285, 0.195)),
                       (1.0, (0.460, 0.430, 0.360))])
    moss = np.clip((fbm(size, 36, base=90, octaves=4) - 0.50) / 0.3, 0, 1)
    alb = mix(alb, np.array([0.055, 0.115, 0.028]), moss * 0.75)
    alb = mix(alb, np.array([0.18, 0.12, 0.055]), litter[..., None] * 0.35)
    alb *= (0.7 + 0.5 * fine)[..., None]
    save("ground_albedo.png", alb)
    save("ground_normal.png", normal_map(h, 32.0))
    save("ground_height.png", h, "L")
    save("ground_rough.png", np.clip(0.72 + 0.22 * (1 - h), 0, 1), "L")

# ---------------------------------------------------------------- gravel
def make_gravel(size=1024):
    f1, f2, cid = voronoi(size, 30, 41)
    dome = np.clip(1.0 - f1 / (f2 + 1e-6), 0, 1) ** 0.7
    fine = fbm(size, 42, base=24, octaves=4)
    h = norm01(0.65 * dome + 0.25 * fine + 0.10 * np.clip(1 - (f2 - f1) / 0.03, 0, 1))
    col = np.stack([0.24 + 0.34 * cid, 0.225 + 0.32 * cid, 0.205 + 0.28 * cid], axis=-1)
    col = mix(col, np.array([0.38, 0.35, 0.30]), (fine[..., None] > 0.55) * 0.5)
    col *= (0.55 + 0.55 * dome)[..., None]
    save("gravel_albedo.png", col)
    save("gravel_normal.png", normal_map(h, 42.0))
    save("gravel_height.png", h, "L")
    save("gravel_rough.png", np.clip(0.55 + 0.3 * (1 - dome), 0, 1), "L")

# ---------------------------------------------------------------- bark
def make_bark(size=512):
    w = warp(size, 51, scale=4.0)
    x, y = np.meshgrid(np.arange(size), np.arange(size), indexing="xy")
    ridges = 0.5 + 0.5 * np.sin(2 * np.pi * 17 * x / size + w * 2.2)
    ridges = ridges ** 2.0
    fine = fbm(size, 52, base=32, octaves=5)
    cracks = sin_bands(size, 7, 53, angle=1.57, warp_amp=2.0)
    cracks = np.clip((cracks - 0.70) * 4.0, 0, 1)
    h = norm01(0.55 * ridges + 0.25 * fine + 0.20 * cracks)
    alb = colorize(h, [(0.0, (0.075, 0.060, 0.043)), (0.4, (0.155, 0.120, 0.080)),
                       (0.75, (0.265, 0.220, 0.165)), (1.0, (0.390, 0.345, 0.275))])
    moss = np.clip((fbm(size, 54, base=40, octaves=4) - 0.55) / 0.3, 0, 1)
    alb = mix(alb, np.array([0.065, 0.125, 0.035]), moss * 0.6)
    alb *= (0.65 + 0.5 * fine)[..., None]
    save("bark_albedo.png", alb)
    save("bark_normal.png", normal_map(h, 34.0))

# ---------------------------------------------------------------- leaf
def make_leaf(size=512):
    y, x = np.meshgrid(np.linspace(0, 1, size), np.linspace(0, 1, size), indexing="ij")
    # central midrib, gently curved
    mid = np.exp(-((x - 0.5 - (y - 0.5) * 0.035) / 0.016) ** 2) * np.clip(1.0 - y * 0.10, 0, 1)
    # pinnate lateral veins, curved forward toward the tip
    veins = np.zeros_like(x)
    for k in range(8):
        vy = 0.10 + k * 0.105
        side = np.abs(x - 0.5)
        curve = vy + side * 0.62 + (side ** 1.7) * 0.12
        d = np.abs(y - curve)
        v = np.exp(-(d / 0.011) ** 2) * np.clip(1.0 - side * 1.25, 0, 1)
        veins = np.maximum(veins, v * (0.55 + 0.45 * (1.0 - k / 8.0)))
    fine = fbm(size, 61, base=24, octaves=4)
    h = norm01(0.50 * mid + 0.23 * veins + 0.27 * fine)
    # darker base, lighter tip, subtle vein highlight
    alb = colorize(h, [(0.0, (0.080, 0.150, 0.035)), (0.40, (0.150, 0.255, 0.060)),
                       (0.72, (0.220, 0.340, 0.095)), (1.0, (0.330, 0.450, 0.135))])
    grad = np.clip(y * 0.65 + 0.35, 0, 1)
    alb = alb * (0.78 + 0.34 * grad)[..., None]
    alb = mix(alb, np.array([0.38, 0.46, 0.14]), np.clip((veins - 0.45) * 1.3, 0, 1)[..., None] * 0.28)
    save("leaf_albedo.png", alb)
    save("leaf_normal.png", normal_map(h, 10.0))


def make_rock_close(size=1024):
    """Low-contrast 1 m rock base: broad mottling, no strata, no busy seams."""
    base = fbm(size, 301, base=96, octaves=5, gain=0.5)
    mid = fbm(size, 302, base=16, octaves=4)
    micro = fbm(size, 303, base=4, octaves=3)
    h = norm01(0.45 * base + 0.35 * mid + 0.20 * micro)
    col = colorize(h, [
        (0.0, (0.145, 0.145, 0.140)),
        (0.45, (0.250, 0.245, 0.232)),
        (0.75, (0.345, 0.335, 0.315)),
        (1.0, (0.450, 0.435, 0.405)),
    ])
    warm = fbm(size, 304, base=8, octaves=3)
    cool = fbm(size, 305, base=6, octaves=3)
    col *= (0.94 + 0.12 * warm)[..., None]
    col *= (0.97 + 0.06 * cool)[..., None]
    save("rock_close_albedo.png", col)
    save("rock_close_normal.png", normal_map(h, 14.0))
    save("rock_close_height.png", h, "L")
    save("rock_close_rough.png", np.clip(0.62 + 0.18 * (1 - h) + 0.08 * micro, 0, 1), "L")


def make_rock_fine(size=1024):
    """Subtle 0.32 m fine layer: 1 cm grains, crystal faces, small pits."""
    grain = fbm(size, 311, base=10, octaves=6, gain=0.6)
    f1, f2, cid = voronoi(size, 28, 312)
    facet = np.clip(1.0 - f1 / 0.62, 0, 1) ** 0.6
    pitn = fbm(size, 313, base=38, octaves=3)
    pit = np.clip((pitn - 0.58) * 6.0, 0, 1)
    h = norm01(0.52 * grain + 0.22 * facet - 0.16 * pit + 0.10 * cid)
    col = colorize(h, [
        (0.0, (0.155, 0.150, 0.142)),
        (0.40, (0.255, 0.248, 0.235)),
        (0.72, (0.360, 0.350, 0.330)),
        (1.0, (0.470, 0.455, 0.430)),
    ])
    tint = np.stack([0.92 + 0.16 * cid, 0.90 + 0.14 * cid, 0.86 + 0.12 * cid], axis=-1)
    col *= tint
    col *= (1.0 - 0.35 * pit)[..., None]
    col *= (0.88 + 0.24 * grain)[..., None]
    save("rock_fine_albedo.png", col)
    save("rock_fine_normal.png", normal_map(h, 42.0))
    save("rock_fine_height.png", h, "L")
    save("rock_fine_rough.png", np.clip(0.60 + 0.20 * (1 - h) + 0.08 * grain, 0, 1), "L")


def make_waterfall(size=512):
    # irregular vertical filaments: broad white water with narrow dark tears
    y, x = np.meshgrid(np.linspace(0, 1, size), np.linspace(0, 1, size), indexing="ij")
    w = warp(size, 82, scale=4.0) * 1.2
    s = np.zeros_like(x)
    for cyc, amp, ph in [(5, 0.52, 0.0), (11, 0.30, 1.7), (23, 0.14, 0.4), (47, 0.07, 2.2)]:
        s += amp * np.sin(2.0 * np.pi * cyc * x + w * (1.0 + cyc * 0.05) + ph)
    s = s / 1.03
    # broad body + bright cores
    body = np.clip((s + 0.62) / 1.10, 0, 1) ** 0.65
    core = np.clip((s - 0.30) / 0.55, 0, 1)
    # break into falling segments, and thin the sheet locally
    seg = fbm(size, 83, base=14, octaves=4)
    vertical = np.clip(0.45 + 0.85 * seg + 0.20 * fbm(size, 84, base=5, octaves=3), 0, 1)
    m = np.clip(body * (0.55 + 0.55 * vertical) + core * 0.55 - 0.12, 0, 1)
    # narrow horizontal impacts / knots
    knots = fbm(size, 85, base=7, octaves=2)
    m *= 1.0 - 0.12 * np.clip((knots - 0.55) * 2.0, 0, 1)
    m = np.clip(m ** 0.85, 0, 1)
    save("waterfall_streaks.png", m, "L")


def make_water(size=512):
    """Water normal + foam mask.

    Both used to be built from pure sine bands / Voronoi cells.  A single
    dominant frequency survives mip-mapping, so any large flat surface (the
    plunge pool) printed it as a paving grid.  These are now built from broad
    band-pass noise only: several octaves, each with a wide band and a mild
    downstream stretch, plus ridged lace for the foam - no dominant
    wavelength, nothing that can tile into a grid.
    """
    h = np.zeros((size, size))
    for i, (wl, amp, asp) in enumerate([(230.0, 0.42, 2.6), (120.0, 0.30, 2.2),
                                        (62.0, 0.20, 2.0), (31.0, 0.13, 1.8),
                                        (16.0, 0.08, 1.6)]):
        h += amp * fft_band(size, wl, 72 + 7 * i, aspect=asp, angle=np.pi * 0.5)
    h += 0.22 * (warp(size, 76, scale=5.0) * 0.5 + 0.5)
    h = norm01(h)
    save("water_normal.png", normal_map(h, 9.0))

    # foam: warped ridged filaments + patchy breakup (lace, not cells)
    r = fbm(size, 78, base=150.0, octaves=4)
    ridge = 1.0 - np.abs(2.0 * r - 1.0)
    ridge = np.clip((ridge - 0.42) * 2.4, 0, 1)
    patch = np.clip((fbm(size, 79, base=260.0, octaves=3) - 0.34) * 2.1, 0, 1)
    lace_n = fbm(size, 80, base=44.0, octaves=4)
    lace_n = norm01(0.6 * lace_n + 0.4 * fft_band(size, 44.0, 813, aspect=2.2, angle=np.pi * 0.5))
    lace = np.clip((lace_n - 0.42) * 2.4, 0, 1)
    foam = norm01(0.70 * ridge * patch + 0.45 * lace + 0.22 * fbm(size, 81, base=22.0, octaves=3))
    save("foam_mask.png", foam, "L")


if __name__ == "__main__":
    make_water()
    make_waterfall()



def make_rock_detail(size=1024):
    """Rock close-up layer (tile 0.32 m): 2-5 cm mineral facets, pebbles,
    pits and hairline fractures, plus 1 mm grain."""
    y, x = np.meshgrid(np.linspace(0, 1, size), np.linspace(0, 1, size), indexing="ij")
    grain = fbm(size, 201, base=20, octaves=6, gain=0.6)
    micro = fbm(size, 202, base=4, octaves=3)

    # faceted mineral cells ~2.3 cm
    f1, f2, cid = voronoi(size, 14, 203)
    edge = np.clip((f2 - f1) / 0.055, 0, 1)
    facet = np.clip(1.0 - f1 / 0.62, 0, 1) ** 0.55
    h = 0.34 * cid + 0.13 * facet + 0.16 * grain

    # embedded pebbles ~4.6 cm
    f1p, f2p, cidp = voronoi(size, 7, 204)
    peb = np.clip((cidp - 0.52) * 3.0, 0, 1) * np.clip(1.0 - f1p / 0.72, 0, 1) ** 0.8
    h += 0.24 * peb

    # solution pits 1-3 cm
    pitn = fbm(size, 205, base=34, octaves=3)
    pit = np.clip((pitn - 0.56) * 7.0, 0, 1) * (0.4 + 0.6 * grain)
    h -= 0.40 * pit

    # hairline fractures, 0.5-1.5 cm wide
    cr = fbm(size, 206, base=70, octaves=4)
    line = np.clip(1.0 - np.abs(2.0 * cr - 1.0) / 0.045, 0, 1)
    line = line ** 0.8
    h -= 0.30 * line

    h = norm01(h + 0.08 * micro)
    alb = colorize(h, [
        (0.0, (0.035, 0.034, 0.032)),
        (0.22, (0.110, 0.105, 0.098)),
        (0.46, (0.230, 0.220, 0.205)),
        (0.72, (0.390, 0.375, 0.350)),
        (1.0, (0.560, 0.545, 0.515)),
    ])
    tint = np.stack([0.80 + 0.40 * cid, 0.78 + 0.38 * cid, 0.74 + 0.34 * cid], axis=-1)
    alb *= tint
    alb = mix(alb, np.array([0.46, 0.44, 0.40]), peb[..., None] * 0.55)
    alb = mix(alb, np.array([0.46, 0.43, 0.38]), (facet * (1 - edge))[..., None] * 0.35)
    alb *= (0.30 + 0.70 * edge)[..., None]
    alb *= (1.0 - 0.55 * pit)[..., None]
    alb *= (1.0 - 0.65 * line)[..., None]
    alb *= (0.78 + 0.30 * grain)[..., None]
    save("rock_detail_albedo.png", alb)
    save("rock_detail_normal.png", normal_map(h, 85.0))
    save("rock_detail_height.png", h, "L")
    save("rock_detail_rough.png", np.clip(0.58 + 0.26 * (1 - h) + 0.10 * grain + 0.10 * pit, 0, 1), "L")


if __name__ == "__main__":
    make_rock_close()
    make_rock_fine()
    make_rock_detail()
    make_rock()
    make_snow()
    make_ground()
    make_gravel()
    make_bark()
    make_leaf()
    print("textures written to", os.path.realpath(OUT))
