#!/usr/bin/env python3
"""AETHER - offline textures for the plunge waterfall (v2.3).

Everything is periodic (seamless) so the fall can scroll it forever.

  fall_sheet.png        R = broad water mass, G = crisp filaments, B = tears
  fall_sheet_normal.png tangent-space normal of the filament relief
  fall_mist.png         RGBA spray/mist card (soft, noisy, seamless)
  fall_drop.png         RGBA single falling-droplet streak sprite

Run:  python3 tools/gen_waterfall.py
"""
import numpy as np
from PIL import Image
import os, math

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
os.makedirs(OUT, exist_ok=True)


def norm01(a):
    a = np.asarray(a, dtype=np.float64)
    mn, mx = a.min(), a.max()
    return (a - mn) / (mx - mn + 1e-9)


def normq(a, q=0.99):
    """Normalize by a high percentile so sparse peaks keep a usable range."""
    a = np.asarray(a, dtype=np.float64)
    hi = np.quantile(a, q)
    return np.clip(a / (hi + 1e-9), 0.0, 1.0)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fft_aniso(size, lx, ly, seed, octaves=3, gain=0.55):
    """Periodic noise whose features are lx px wide and ly px tall."""
    acc = np.zeros((size, size))
    amp = 1.0
    for o in range(octaves):
        rng = np.random.default_rng(seed + 977 * o)
        w = rng.standard_normal((size, size))
        F = np.fft.fft2(w)
        fy, fx = np.meshgrid(np.fft.fftfreq(size), np.fft.fftfreq(size), indexing="ij")
        r = np.sqrt((fx * lx) ** 2 + (fy * ly) ** 2)
        band = np.exp(-0.5 * ((r - 1.0) / 0.55) ** 2)
        acc += amp * norm01(np.real(np.fft.ifft2(F * band)))
        amp *= gain
        lx *= 0.55
        ly *= 0.55
    return norm01(acc)


def fft_band_iso(size, wavelength, seed, aspect=1.0, angle=0.0):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((size, size))
    F = np.fft.fft2(w)
    fy, fx = np.meshgrid(np.fft.fftfreq(size), np.fft.fftfreq(size), indexing="ij")
    ca, sa = math.cos(angle), math.sin(angle)
    u = fx * ca + fy * sa
    v = -fx * sa + fy * ca
    r = np.sqrt((u * aspect) ** 2 + v ** 2)
    fc = 1.0 / max(wavelength, 1.0)
    band = np.exp(-0.5 * ((r - fc) / (0.45 * fc + 1e-6)) ** 2)
    return norm01(np.real(np.fft.ifft2(F * band)))


def fbm(size, seed, base=512.0, octaves=6, gain=0.55, aspect=1.0, angle=0.0):
    v = np.zeros((size, size))
    amp = 1.0
    wl = base
    for o in range(octaves):
        v += amp * (fft_band_iso(size, wl, seed + 97 * o, aspect, angle) * 2.0 - 1.0)
        wl = max(wl * 0.5, 2.0)
        amp *= gain
    return norm01(v)


def normal_map(h, strength):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    n = np.stack([-dx * strength, -dy * strength, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return (n * 0.5 + 0.5)


def save(name, arr, mode=None):
    a = np.clip(arr, 0.0, 1.0)
    if a.ndim == 3 and a.shape[2] == 3:
        img = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGB")
    elif a.ndim == 3 and a.shape[2] == 4:
        img = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGBA")
    else:
        img = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "L")
    img.save(os.path.join(OUT, name))
    print("  ", name, img.size)


# ---------------------------------------------------------------- sheet
def make_sheet(size=2048):
    print("fall_sheet")
    x = (np.arange(size) + 0.5) / size
    rng = np.random.default_rng(4207)

    # --- 1. a 1-D curtain of filaments sampled along x, then warped slowly as
    #        it falls.  The 1-D skeleton is what keeps every streak vertically
    #        coherent; the warp keeps them from being ruled lines.
    prof = np.zeros(size)
    # bundles of water 0.3 .. 2.6 m across (the tile spans ~34 m), plus a fine
    # filament overlay for the sub-metre structure
    for i in range(86):
        cx = rng.random()
        bw = (18.0 + 145.0 * rng.random() ** 1.7) / size
        amp = 0.5 + 0.5 * rng.random() ** 0.8
        d = np.abs(x - cx)
        d = np.minimum(d, 1.0 - d)
        prof += amp * np.exp(-0.5 * (d / bw) ** 2)
    for i in range(150):
        cx = rng.random()
        bw = (2.5 + 9.0 * rng.random() ** 2.0) / size
        amp = 0.20 + 0.35 * rng.random()
        d = np.abs(x - cx)
        d = np.minimum(d, 1.0 - d)
        prof += amp * np.exp(-0.5 * (d / bw) ** 2)
    prof = normq(prof, 0.985)

    warp = (fft_aniso(size, 90.0, 1200.0, 11, 2) - 0.5) * 2.0
    idx = ((x + warp * 0.028) % 1.0 * size).astype(np.int32) % size
    strand = prof[idx]

    # --- 2. break the strands along their length.  The modulation must be
    #        2-D and short-range, otherwise it prints horizontal rows across
    #        the whole curtain.
    modu = fft_aniso(size, 150.0, 1600.0, 21, 2)
    modu2 = fft_aniso(size, 420.0, 4200.0, 22, 2)
    strand *= 0.68 + 0.62 * smoothstep(0.12, 0.70, modu)
    strand *= 0.88 + 0.26 * smoothstep(0.18, 0.78, modu2)
    strand = normq(strand, 0.99)

    # --- 3. broad masses and thin spots
    body = 0.55 * fft_aniso(size, 260.0, 420.0, 31, 3) + 0.45 * fft_aniso(size, 90.0, 190.0, 32, 2)
    body = norm01(body)
    holes = fft_aniso(size, 110.0, 230.0, 41, 3)

    tear = smoothstep(0.60, 0.86, holes * 0.85 + body * 0.22)

    # --- 4. bubbles / spray sparkle
    spark = smoothstep(0.68, 0.96, fft_aniso(size, 5.0, 8.0, 51, 2))

    # --- 5. compress: mostly white water with narrow dark gaps
    mass = norm01(0.72 * strand + 0.46 * body) - 0.16 * tear
    mass = smoothstep(0.10, 0.86, mass) ** 0.86
    filament = smoothstep(0.28, 0.90, normq(strand, 0.99))

    rgb = np.stack([mass, filament, np.clip(tear * 0.55 + spark * 0.30, 0, 1)], axis=-1)
    save("fall_sheet.png", rgb)
    save("fall_sheet_normal.png", normal_map(0.70 * filament + 0.30 * mass, 22.0))


# ---------------------------------------------------------------- mist card
def make_mist(size=512):
    print("fall_mist")
    y, x = np.meshgrid((np.arange(size) + 0.5) / size,
                       (np.arange(size) + 0.5) / size, indexing="ij")
    n1 = fbm(size, 101, base=size / 3.0, octaves=5)
    n2 = fbm(size, 102, base=size / 8.0, octaves=4)
    n3 = fbm(size, 103, base=size / 22.0, octaves=3)
    # rising plume: noise stretched vertically, denser at the bottom
    v = 0.55 * n1 + 0.30 * n2 + 0.15 * n3
    radial = np.sqrt((x - 0.5) ** 2 + ((y - 0.62) * 1.25) ** 2) * 2.0
    edge = smoothstep(1.05, 0.35, radial)
    a = smoothstep(0.28, 0.78, v) * edge
    a *= 0.55 + 0.45 * (1.0 - y)
    a = np.clip(a, 0, 1)
    rgb = np.stack([0.93 - 0.03 * n2, 0.96 - 0.02 * n2, 0.99 + 0.0 * n2], axis=-1)
    save("fall_mist.png", np.concatenate([rgb, a[..., None]], axis=-1))


# ---------------------------------------------------------------- droplet
def make_drop(w=64, h=256):
    print("fall_drop")
    x = (np.arange(w) + 0.5) / w * 2.0 - 1.0
    y = (np.arange(h) + 0.5) / h
    X, Y = np.meshgrid(x, y, indexing="xy")
    # thin vertical streak: sharp core, soft optical falloff, tapered ends
    core = np.exp(-(X / 0.22) ** 2) * 0.9 + np.exp(-(X / 0.55) ** 2) * 0.35
    taper = smoothstep(0.0, 0.10, Y) * smoothstep(1.0, 0.55, Y)
    a = np.clip(core * (0.45 + 0.55 * taper), 0, 1)
    # a couple of satellite beads in the tail
    a += np.exp(-(((X - 0.12) / 0.10) ** 2 + ((Y - 0.80) / 0.05) ** 2)) * 0.5
    a = np.clip(a, 0, 1)
    rgb = np.ones((h, w, 3)) * 0.97
    save("fall_drop.png", np.concatenate([rgb, a[..., None]], axis=-1))


if __name__ == "__main__":
    make_sheet()
    make_mist()
    make_drop()
    print("done")