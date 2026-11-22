#!/usr/bin/env python3
"""AETHER - offline rock face baker.

Two products, both baked once and shipped as files:

1. assets/meshes/rock_face.bin
   A 6.4 x 4.6 m vertical cliff face as a *height field mesh* with a graded
   grid (8 mm in the hero window, 16 mm at the borders).  It carries the
   metre/decimetre structure that a texture cannot: stacked beds with
   undercut lips, joint-bounded blocks with their own plane and tilt, chipped
   corners, spall scars, fractures, and baked sky/sun occlusion in COLOR.

2. assets/textures/rock_face_{albedo,normal,height,rough}.png
   A 2.0 m seamless tile carrying only the sub-centimetre material: sparse
   mineral grains, pits, dust film, iron staining, lichen flecks.  Low
   contrast on purpose - the mesh supplies the form, this supplies the stuff.

Run:  python3 tools/gen_rockface.py [--tex] [--mesh] [--preview]
"""
import numpy as np
from PIL import Image
import os, math, sys, struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
OUT_TEX = os.path.join(ROOT, "assets", "textures")
OUT_MESH = os.path.join(ROOT, "assets", "meshes")
os.makedirs(OUT_TEX, exist_ok=True)
os.makedirs(OUT_MESH, exist_ok=True)

# ------------------------------------------------------------------ helpers
def vn(X, Y, scale, seed):
    """Smooth value noise in [0,1] on arbitrary coordinates."""
    x = X / scale
    y = Y / scale
    ix = np.floor(x)
    iy = np.floor(y)
    fx = x - ix
    fy = y - iy
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)

    def h(a, b):
        v = np.sin(a * 127.1 + b * 311.7 + seed * 13.13) * 43758.5453
        return v - np.floor(v)

    a = h(ix, iy)
    b = h(ix + 1.0, iy)
    c = h(ix, iy + 1.0)
    d = h(ix + 1.0, iy + 1.0)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def add_bump(z, xs, ys, cx, cy, rx, ry, amp, power=1.4, tilt_amp=0.0, rng=None):
    """Add a localised weathering bump/dent to the height field (sliced)."""
    i0 = max(int(np.searchsorted(xs, cx - rx)) - 1, 0)
    i1 = min(int(np.searchsorted(xs, cx + rx)) + 2, len(xs))
    j0 = max(int(np.searchsorted(ys, cy - ry)) - 1, 0)
    j1 = min(int(np.searchsorted(ys, cy + ry)) + 2, len(ys))
    if i1 <= i0 or j1 <= j0:
        return
    sx = xs[i0:i1][None, :]
    sy = ys[j0:j1][:, None]
    d = ((sx - cx) / rx) ** 2 + ((sy - cy) / ry) ** 2
    fall = np.clip(1.0 - d, 0.0, 1.0) ** power
    if rng is not None and tilt_amp > 0.0:
        fall = fall * (1.0 + tilt_amp * ((sx - cx) / rx))
    z[j0:j1, i0:i1] += amp * fall



def facet_layer(X, Y, cell, seed, off_amp, tilt_amp, jitter=0.85):
    """Mosaic of planar chips (jittered Voronoi).  Each cell gets its own plane,
    so the layer is full of sharp creases exactly like a fractured rock skin."""
    def hh(a, b, c):
        v = np.sin(a * 127.1 + b * 311.7 + c * 74.7 + seed * 3.77) * 43758.5453
        return v - np.floor(v)

    gx = np.floor(X / cell)
    gy = np.floor(Y / cell)
    best = np.full(X.shape, 1e9)
    bx = np.zeros_like(X)
    by = np.zeros_like(X)
    bid = np.zeros_like(X)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx = gx + ox
            cy = gy + oy
            sx = (cx + 0.5 + jitter * (hh(cx, cy, 1.0) - 0.5)) * cell
            sy = (cy + 0.5 + jitter * (hh(cx, cy, 2.0) - 0.5)) * cell
            d = (X - sx) ** 2 + (Y - sy) ** 2
            m = d < best
            best = np.where(m, d, best)
            bx = np.where(m, sx, bx)
            by = np.where(m, sy, by)
            bid = np.where(m, hh(cx, cy, 3.0), bid)
    # per-cell random plane
    off = (bid - 0.5) * 2.0 * off_amp
    tx = (hh(bid * 91.7, bid * 13.3, 4.0) - 0.5) * 2.0 * tilt_amp
    ty = (hh(bid * 37.1, bid * 61.9, 5.0) - 0.5) * 2.0 * tilt_amp
    return off + tx * (X - bx) + ty * (Y - by)

def norm01(a):
    a = a.astype(np.float64)
    mn, mx = a.min(), a.max()
    return (a - mn) / (mx - mn + 1e-9)


def fft_band(size, wavelength, seed, aspect=1.0, angle=0.0):
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


def voronoi(size, cells, seed):
    rng = np.random.default_rng(seed)
    pts = rng.random((cells, cells, 2))
    rnd = rng.random((cells, cells))
    xs = (np.arange(size) + 0.5) / size * cells
    gx = np.floor(xs).astype(np.int64)
    fx = xs - gx
    X, Y = np.meshgrid(fx, fx, indexing="xy")
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


def normal_map(h, strength=2.0):
    h = h.astype(np.float64)
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.clip(np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5, 0, 1)


def save_rgb(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB").save(
        os.path.join(OUT_TEX, name))


def save_l(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "L").save(
        os.path.join(OUT_TEX, name))


def box_blur(a, r, axis):
    """Periodic box blur along one axis (wrap edges)."""
    if r <= 0:
        return a
    idx = np.arange(-r, a.shape[axis] + r) % a.shape[axis]
    pad = np.take(a, idx, axis=axis)
    zs = list(pad.shape)
    zs[axis] = 1
    c = np.concatenate([np.zeros(zs, dtype=np.float64), np.cumsum(pad, axis=axis, dtype=np.float64)], axis=axis)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return (hi - lo) / float(2 * r + 1)


def blur2(a, r):
    return box_blur(box_blur(a, r, 0), r, 1)


# ------------------------------------------------------- 2 m material tile
def make_struct_textures(size=2048):
    """Seamless *6 m* structural tile at 2.9 mm/px.

    Carries the scale a 2-6 m camera sees: fracture plates at their own angle,
    open joints, bedding ledges, flake scars, lichen and seep.  All of it in
    normal + AO - geometry this crisp is impossible on a height-field mesh.
    """
    m_per = 6.0
    rng = np.random.default_rng(7001)
    yy, xx = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")

    def pw(sx, sy, seed=1.0):
        gx = size / sx
        gy = size / sy
        X = xx / sx
        Y = yy / sy
        ix = np.floor(X); iy = np.floor(Y)
        fx = X - ix; fy = Y - iy
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        def hh(a, b, c):
            v = np.sin(a * 127.1 + b * 311.7 + c * 74.7 + seed * 17.3) * 43758.5453
            return v - np.floor(v)
        a = hh(ix % gx, iy % gy, 1.0); b = hh((ix + 1) % gx, iy % gy, 1.0)
        c = hh(ix % gx, (iy + 1) % gy, 1.0); d = hh((ix + 1) % gx, (iy + 1) % gy, 1.0)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

    def facets(cell_px, off_amp, tilt_amp, seed):
        rng2 = np.random.default_rng(seed)
        gx = size // cell_px
        ox = rng2.uniform(-0.38, 0.38, (gx, gx))
        oy = rng2.uniform(-0.38, 0.38, (gx, gx))
        off = rng2.uniform(-off_amp, off_amp, (gx, gx))
        tx = rng2.uniform(-tilt_amp, tilt_amp, (gx, gx))
        ty = rng2.uniform(-tilt_amp, tilt_amp, (gx, gx))
        cx = (np.floor(xx / cell_px).astype(np.int64)) % gx
        cy = (np.floor(yy / cell_px).astype(np.int64)) % gx
        u = (xx % cell_px) / cell_px - 0.5
        v = (yy % cell_px) / cell_px - 0.5
        best = np.full(xx.shape, 1e9)
        bdx = np.zeros(xx.shape); bdy = np.zeros(xx.shape)
        bidx = np.zeros_like(cx); bidy = np.zeros_like(cy)
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                nx = (cx + di) % gx
                ny = (cy + dj) % gx
                dx = u - (di + ox[ny, nx])
                dy = v - (dj + oy[ny, nx])
                d = dx * dx + dy * dy
                m = d < best
                best = np.where(m, d, best)
                bdx = np.where(m, dx, bdx); bdy = np.where(m, dy, bdy)
                bidx = np.where(m, nx, bidx); bidy = np.where(m, ny, bidy)
        return (off[bidy, bidx] + tx[bidy, bidx] * bdx + ty[bidy, bidx] * bdy,
                bidx, bidy)

    # ---- broad terraced mass: 3-4 stepped ledges, warped so nothing is
    # axis-aligned.  This is the bedding/ledge structure at 1-3 m.
    warp = 0.16 * (pw(210, 210, 2) - 0.5) + 0.07 * (pw(70, 70, 3) - 0.5)
    nlev = pw(520, 520, 4) + warp
    t = nlev * 3.6 + 0.45 * (pw(120, 120, 5) - 0.5)
    lev = np.floor(t)
    fr = t - lev
    step = np.clip((fr - 0.55) / 0.38, 0, 1)
    step = step * step * (3 - 2 * step)
    h = 0.5 + 0.30 * (lev - 1.5) + 0.30 * step
    h += 0.13 * (pw(150, 150, 6) - 0.5)
    h += 0.07 * (pw(44, 44, 7) - 0.5)

    # ---- fracture ridges: sparse, irregular, from ridged noise (never a net)
    rid = 1.0 - np.abs(2.0 * pw(330, 330, 8) - 1.0)
    rid = np.clip((rid - 0.80) / 0.20, 0, 1) ** 2.2
    rid2 = 1.0 - np.abs(2.0 * pw(120, 120, 9) - 1.0)
    rid2 = np.clip((rid2 - 0.86) / 0.14, 0, 1) ** 3.0
    joints = np.clip(rid * 1.0 + rid2 * 0.55, 0, 1)
    h -= 0.26 * joints

    h = norm01(h)
    # erode a touch: 1 px only, so rims stay edges
    h = 0.75 * h + 0.25 * box_blur(box_blur(h, 1, 0), 1, 1)

    gx0 = np.abs(np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    gy0 = np.abs(np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    p90 = np.percentile(np.hypot(gx0, gy0), 90.0)
    nstr = float(0.45 / max(p90, 1e-5))

    # ------------------------------------------------------------ colour
    cav = norm01(np.clip(blur2(h, 4) - h, 0, None))
    ao = np.clip(1.0 - 0.9 * cav, 0.18, 1.0)
    broad = pw(340, 340, 5)
    mid = pw(96, 96, 6)
    base = np.array([0.400, 0.398, 0.392])
    warm = np.array([0.450, 0.418, 0.362])
    cool = np.array([0.336, 0.356, 0.392])
    t1 = np.clip((broad - 0.3) * 1.5, 0, 1)[..., None]
    t2 = np.clip((mid - 0.35) * 1.3, 0, 1)[..., None]
    col = base * (1 - 0.45 * t1) + warm * 0.45 * t1
    col = col * (1 - 0.35 * t2) + cool * 0.35 * t2
    col = col * (0.50 + 0.50 * ao[..., None])
    # dark seams hold shadow and dirt
    col *= (1.0 - 0.55 * joints)[..., None]
    col *= (1.0 - 0.35 * np.clip(-(h - 0.5) * 3.0, 0, 1))[..., None]
    # lichen crusts and damp streaks
    lc = pw(70, 70, 7)
    lm = np.clip((lc - 0.62) * 4.0, 0, 1) * np.clip((pw(4, 4, 8) - 0.2) * 2.0, 0, 1)
    col = col * (1 - 0.30 * lm[..., None]) + np.array([0.45, 0.45, 0.40]) * 0.30 * lm[..., None]
    streak = np.clip((pw(160, 90, 9) - 0.58) * 3.0, 0, 1) * np.clip((pw(26, 900, 10) - 0.25) * 1.6, 0, 1)
    col *= (1.0 - 0.30 * streak)[..., None]
    dust = np.clip((0.45 - h) * 4.0, 0, 1) * np.clip(pw(60, 60, 11) * 1.5, 0, 1)
    col = col * (1 - 0.2 * dust[..., None]) + np.array([0.55, 0.54, 0.51]) * 0.2 * dust[..., None]

    rough = np.clip(0.60 + 0.22 * (1 - ao) + 0.14 * lm - 0.10 * streak + 0.06 * (mid - 0.5),
                    0.22, 0.96)

    save_rgb("rock_struct_albedo.png", col)
    save_rgb("rock_struct_normal.png", normal_map(h, nstr))
    save_l("rock_struct_height.png", h)
    save_l("rock_struct_rough.png", rough)
    print("[struct] 6.0 m tile %d^2 (%.2f mm/px) nstr=%.1f p90=%.3f"
          % (size, m_per * 1000 / size, nstr, p90))
    return h


def make_face_textures(size=2048):
    """Seamless 1.4 m rock material tile at 0.68 mm/px.

    This is where the sub-centimetre rock lives: chipped facets, cracks with
    V-profiles, solution pits, grit, lichen and grain.  The *shading* of that
    relief comes from the baked normal map plus baked AO in the albedo, which
    is the only way to get crisp millimetre edges at a 1 m camera distance.
    """
    m_per = 2.0
    P = size / m_per                      # pixels per metre
    rng = np.random.default_rng(916)
    yy, xx = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")

    def pw(sx, sy):
        """periodic value noise, sx/sy in pixels"""
        gx = size / sx
        gy = size / sy
        X = xx / sx
        Y = yy / sy
        ix = np.floor(X); iy = np.floor(Y)
        fx = X - ix; fy = Y - iy
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        def hh(a, b, c):
            v = np.sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453
            return v - np.floor(v)
        a = hh(ix % gx, iy % gy, 1.0); b = hh((ix + 1) % gx, iy % gy, 1.0)
        c = hh(ix % gx, (iy + 1) % gy, 1.0); d = hh((ix + 1) % gx, (iy + 1) % gy, 1.0)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

    # ---------------------------------------------------------- height field
    # chipped stone skin: two scales of planar facets on a jittered grid
    def facets_px(cell_px, off_amp, tilt_amp, seed):
        rng2 = np.random.default_rng(seed)
        gx = size // cell_px
        ox = rng2.uniform(-0.35, 0.35, (gx, gx))
        oy = rng2.uniform(-0.35, 0.35, (gx, gx))
        off = rng2.uniform(-off_amp, off_amp, (gx, gx))
        tx = rng2.uniform(-tilt_amp, tilt_amp, (gx, gx))
        ty = rng2.uniform(-tilt_amp, tilt_amp, (gx, gx))
        cx = (np.floor(xx / cell_px).astype(np.int64)) % gx
        cy = (np.floor(yy / cell_px).astype(np.int64)) % gx
        u = (xx % cell_px) / cell_px - 0.5
        v = (yy % cell_px) / cell_px - 0.5
        best = np.full(xx.shape, 1e9)
        bdx = np.zeros(xx.shape); bdy = np.zeros(xx.shape)
        bidx = np.zeros_like(cx); bidy = np.zeros_like(cy)
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                nx = (cx + di) % gx
                ny = (cy + dj) % gx
                dx = u - (di + ox[ny, nx])
                dy = v - (dj + oy[ny, nx])
                d = dx * dx + dy * dy
                m = d < best
                best = np.where(m, d, best)
                bdx = np.where(m, dx, bdx)
                bdy = np.where(m, dy, bdy)
                bidx = np.where(m, nx, bidx); bidy = np.where(m, ny, bidy)
        return off[bidy, bidx] + tx[bidy, bidx] * bdx + ty[bidy, bidx] * bdy

    # fractal roughness: every scale from 9 cm down to 1.4 mm
    lib = np.zeros_like(xx, dtype=np.float64)
    for px_sz, amp in ((128, 0.50), (64, 0.36), (32, 0.27), (16, 0.22),
                       (8, 0.18), (4, 0.14), (2, 0.095)):
        lib += amp * (pw(px_sz, px_sz) - 0.5)
    # chipped planes: a hint of facets, not a cracked-mud net
    lib += 0.11 * facets_px(37, 0.75, 0.65, 4001)
    lib += 0.10 * facets_px(95, 0.50, 0.45, 4002)
    h = 0.5 + lib
    # soften the facet steps by <1 px so they read as worn edges, not jaggies
    h = 0.6 * h + 0.4 * box_blur(h, 1, 0)
    h = 0.6 * h + 0.4 * box_blur(h, 1, 1)

    # cracks: wandering polylines, V profile, 1-4 px wide
    crack = np.zeros_like(h)
    for i in range(3):
        r3 = np.random.default_rng(4100 + i)
        x0 = r3.uniform(0, size)
        amp1 = r3.uniform(20, 90)
        f1 = r3.uniform(0.6, 1.8)
        ph = r3.uniform(0, 6.28)
        amp2 = r3.uniform(5, 22)
        f2 = r3.uniform(2.5, 6.0)
        # periodic in y: use sines of y/size*2pi
        t = yy / size * 2 * math.pi
        cxline = x0 + amp1 * np.sin(t * f1 + ph) + amp2 * np.sin(t * f2 + ph * 1.7)
        d = np.abs(((xx - cxline + size * 0.5) % size) - size * 0.5)
        w = r3.uniform(2.0, 4.4)
        g = np.clip(1.0 - d / w, 0, 1) ** 0.7
        crack = np.maximum(crack, g * r3.uniform(0.30, 0.85))
    h -= 0.22 * crack

    # solution pits: 2-14 px
    for i in range(700):
        r4 = np.random.default_rng(4200 + i)
        cx0 = r4.uniform(0, size); cy0 = r4.uniform(0, size)
        rx = r4.uniform(1.2, 7.0); ry = rx * r4.uniform(0.6, 1.4)
        dep = r4.uniform(0.02, 0.10)
        i0 = int(cx0 - rx - 2); i1 = int(cx0 + rx + 3)
        j0 = int(cy0 - ry - 2); j1 = int(cy0 + ry + 3)
        sx = xx[j0 % size:j1 % size, i0 % size:i1 % size]
        if sx.size == 0:
            continue
        dx = (np.arange(i0, i1)[None, :] - cx0) / rx
        dy = (np.arange(j0, j1)[:, None] - cy0) / ry
        d = dx * dx + dy * dy
        fall = np.clip(1 - d, 0, 1) ** 0.8
        js = np.arange(j0, j1) % size
        is_ = np.arange(i0, i1) % size
        h[np.ix_(js, is_)] -= dep * fall

    # grain: 1-2 px, low amplitude
    gn = np.random.default_rng(4300)
    h += 0.012 * (box_blur(gn.random((size, size)) - 0.5, 1, 0))
    h = norm01(h)

    # calibrate the normal strength so the surface is not flat: 90th percentile
    # slope lands near 0.4 (22 deg), which is what weathered stone looks like.
    gx0 = np.abs(np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    gy0 = np.abs(np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    p90 = np.percentile(np.hypot(gx0, gy0), 90.0)
    nstr = float(0.40 / max(p90, 1e-5))

    # ---------------------------------------------------------- occlusion
    cav = np.clip(blur2(h, 3) - h, 0, None)
    cav = norm01(cav)
    ao = np.clip(1.0 - 0.85 * cav, 0.25, 1.0)

    # ---------------------------------------------------------- albedo
    broad = pw(420, 420)
    mid = pw(140, 140)
    fine = pw(38, 38)
    base = np.array([0.392, 0.392, 0.390])
    warm = np.array([0.438, 0.410, 0.360])
    cool = np.array([0.340, 0.362, 0.398])
    t1 = np.clip((broad - 0.3) * 1.6, 0, 1)[..., None]
    t2 = np.clip((mid - 0.35) * 1.4, 0, 1)[..., None]
    col = base * (1 - 0.40 * t1) + warm * 0.40 * t1
    col = col * (1 - 0.30 * t2) + cool * 0.30 * t2
    col *= (0.94 + 0.12 * fine)[..., None]
    # dirt and grit collect in the relief: this is the AO term, warm grey
    col = col * (0.55 + 0.45 * ao[..., None])
    col = col * (1 - 0.25 * (1 - ao[..., None])) + np.array([0.30, 0.28, 0.25]) * 0.25 * (1 - ao[..., None])

    # mineral grains: sparse, clustered, 1-3 px
    gcl = pw(90, 90)
    gsel = np.clip((gcl - 0.30) * 1.7, 0, 1) ** 1.5
    qtz = ((rng.random((size, size)) > 0.9975) * (0.25 + 0.75 * gsel)).astype(np.float64)
    qtz = np.clip(blur2(qtz, 1) * 2.0, 0, 1)
    dark = ((rng.random((size, size)) > 0.9980) * (0.3 + 0.7 * (1 - gsel))).astype(np.float64)
    dark = np.clip(blur2(dark, 1) * 1.8, 0, 1)
    col *= (1 - 0.30 * dark[..., None])
    # cracks read as dark seams: AO from the height alone is too weak at 2 px
    col *= (1.0 - 0.22 * crack)[..., None]
    col = col * (1 - 0.28 * qtz[..., None]) + np.array([0.74, 0.75, 0.76]) * 0.28 * qtz[..., None]

    # lichen: crusty patches, speckled edges, 2-8 cm
    lcl = pw(46, 46)
    lmask = np.clip((lcl - 0.78) * 7.0, 0, 1) * 0.55
    speck = pw(3, 3)
    lmask = np.clip(lmask * (0.55 + 0.9 * speck) - 0.12, 0, 1)
    col = col * (1 - 0.40 * lmask[..., None]) + np.array([0.46, 0.50, 0.38]) * 0.40 * lmask[..., None]

    rough = np.clip(0.62 + 0.18 * (1 - ao) + 0.10 * (mid - 0.5) - 0.22 * qtz
                    + 0.12 * lmask + 0.08 * dark, 0.22, 0.96)

    save_rgb("rock_face_albedo.png", col)
    save_rgb("rock_face_normal.png", normal_map(h, nstr))
    save_l("rock_face_height.png", h)
    save_l("rock_face_rough.png", rough)
    print("[face] 2.0 m tile %d^2 (%.2f mm/px)  ao_min=%.2f  nstr=%.1f  p90slope=%.3f"
          % (size, m_per * 1000 / size, ao.min(), nstr, p90))
    # widen the crack AO a touch so it holds shadow instead of a drawn line
    h = h


# ------------------------------------------------------------ wall geometry
W = 6.4          # panel width  (m)
H = 4.6          # panel height (m)
FINE = 0.0042    # hero grid spacing (m)
COARSE = 0.015   # border grid spacing (m)
WIN = 1.55       # hero window half width (m) around x=0
WIN_Y = (0.85, 2.55)   # hero window in y


def graded_axis(lo, hi, flo, fhi, fstep, cstep):
    core = np.arange(flo, fhi + 1e-9, fstep)
    left = np.arange(lo, flo - 1e-9, cstep)
    right = np.arange(fhi + cstep, hi + 1e-9, cstep)
    a = np.concatenate([left, core, right])
    a = np.clip(a, lo, hi)
    return np.unique(np.round(a, 5))


def build_height():
    xs = graded_axis(-W / 2, W / 2, -WIN, WIN, FINE, COARSE)
    ys = graded_axis(0.0, H, WIN_Y[0], WIN_Y[1], FINE, COARSE)
    X, Y = np.meshgrid(xs, ys)
    nx, ny = X.shape[1], X.shape[0]
    print("[face] grid %d x %d = %d verts (%.1f mm hero, %.0f mm border)"
          % (nx, ny, nx * ny, FINE * 1000, COARSE * 1000))

    rng = np.random.default_rng(20261116)

    # ---- large massing: weathered wall, leaning back, lumpy at 0.5-3 m
    z = np.zeros_like(X)
    z += 0.055 * (vn(X, Y, 2.6, 1) - 0.5) * 2.0
    z += 0.040 * (vn(X, Y, 1.15, 2) - 0.5) * 2.0
    z += 0.022 * (vn(X, Y, 0.52, 3) - 0.5) * 2.0
    z -= 0.085 * (Y / H)                      # leans back a little
    # two big hollows where slabs have come away
    z -= 0.060 * np.exp(-(((X - 1.30) / 0.85) ** 2 + ((Y - 1.05) / 0.75) ** 2))
    z -= 0.040 * np.exp(-(((X + 2.05) / 0.60) ** 2 + ((Y - 3.30) / 0.55) ** 2))
    # and one proud buttress
    z += 0.045 * np.exp(-(((X + 0.95) / 0.95) ** 2 + ((Y - 2.30) / 1.15) ** 2))
    # spalled slabs: broad shallow concave patches (5-20 cm)
    for i in range(90):
        cx = rng.uniform(-W / 2, W / 2)
        cy = rng.uniform(0.1, H - 0.05)
        rx = rng.uniform(0.045, 0.20)
        ry = rng.uniform(0.035, 0.15)
        dep = rng.uniform(0.003, 0.011) * (1.0 - 0.5 * rng.random())
        m = (np.abs(X - cx) < rx) & (np.abs(Y - cy) < ry)
        d = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2
        z -= m * dep * np.clip(1 - d, 0, 1) ** 0.7

    # ---- bedding: 5 uneven bands, offset as *smooth* ledges.  Any hard step in
    # a height field renders as a 1-vertex black line, so every transition here
    # is an S-curve 7 cm wide: it reads as a ledge, not a sawn groove.
    thick = np.array([0.95, 0.62, 1.22, 0.78, 1.03])
    thick = thick * (H / thick.sum())
    tilt = 0.075
    wob = Y + 0.045 * (vn(X, Y * 0.2, 1.5, 11) - 0.5) * 2.0 + 0.014 * np.sin(X * 2.3 + 0.8)
    bounds = np.cumsum(thick)
    bed_off = np.array([-0.042, 0.018, -0.014, 0.036, -0.024])
    bed_hue = np.array([-0.05, 0.04, -0.03, 0.05, -0.02])
    yb = wob - tilt * X
    for k in range(1, len(thick)):
        soft = np.tanh((yb - bounds[k - 1]) / 0.016) * 0.5 + 0.5
        z += (bed_off[k] - bed_off[k - 1]) * soft
    z += bed_off[0]

    blk_val = np.ones_like(X) * 1.0
    blk_hue = np.zeros_like(X)
    blk_rough = np.ones_like(X) * 0.66
    lay = np.searchsorted(bounds, yb).clip(0, len(thick) - 1)
    blk_hue = bed_hue[lay]

    # ---- weathered lumps: the 5-30 cm convex/concave form of a cliff face
    for i in range(700):
        cx = rng.uniform(-W / 2, W / 2)
        cy = rng.uniform(-0.05, H + 0.05)
        r = rng.uniform(0.020, 0.200)
        ry = r * rng.uniform(0.65, 1.55)
        amp = rng.normal(0.0, 0.0170)
        add_bump(z, xs, ys, cx, cy, r, ry, amp, power=rng.uniform(1.0, 2.2))

    # ---- hollows that hold grit and shadow
    for i in range(150):
        cx = rng.uniform(-W / 2, W / 2)
        cy = rng.uniform(0.0, H)
        r = rng.uniform(0.012, 0.055)
        ry = r * rng.uniform(0.7, 1.4)
        dep = rng.uniform(0.003, 0.011)
        add_bump(z, xs, ys, cx, cy, r, ry, -dep, power=rng.uniform(0.8, 1.5))

    # ---- tight, low-amplitude roughness so faces are not billiard flat
    z += 0.0016 * np.sin(X * 43.0 + Y * 29.0) + 0.0012 * np.sin(X * 71.0 - Y * 53.0)

    # erode: the blockwork is a scaffold, not the final shape.  Two rounds of
    # smoothing at 4-12 mm take the machined edge off every step and lip.
    z = 0.62 * z + 0.38 * box_blur(box_blur(z, 3, 0), 3, 1)
    z = 0.72 * z + 0.28 * box_blur(box_blur(z, 1, 0), 1, 1)

    # normals from the graded grid
    gy, gx = np.gradient(z, ys, xs)
    n = np.stack([-gx, -gy, np.ones_like(z)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)

    # ------------------------------------------------ baked occlusion
    cav = np.zeros_like(z)
    for r_px, wgt in ((2, 0.55), (6, 0.32), (16, 0.22)):
        cav += wgt * np.clip(blur2(z, r_px) - z, 0, None)
    cav = norm01(cav)
    ao = np.clip(1.0 - 0.80 * cav, 0.40, 1.0)

    # overhang shadow: anything proud above within ~20 cm darkens a band below
    up = z[::-1, :]
    above = np.maximum.accumulate(up, axis=0)[::-1, :]
    sh = np.zeros_like(z)
    for k in (3, 8, 18, 34):
        sh = np.maximum(sh, np.roll(above, -k, axis=0) - z)  # rolled up
    sh = norm01(np.clip(sh, 0, None))
    ao *= np.clip(1.0 - 0.45 * sh, 0.45, 1.0)

    # sun visibility: march along the light's ground projection
    sun_xy = np.array([0.812, -0.497])       # direction light *travels* (x, y)
    sun_z = 0.302
    vis = np.ones_like(z)
    for t in np.arange(0.008, 0.32, 0.008):
        sx = X - sun_xy[0] * t
        sy = Y - sun_xy[1] * t
        ix = np.clip(np.searchsorted(xs, sx), 1, len(xs) - 2)
        iy = np.clip(np.searchsorted(ys, sy), 1, len(ys) - 2)
        hh = z[iy, ix]
        vis = np.minimum(vis, np.clip((hh - (z + sun_z * t)) / 0.006, 0, 1))
    ao *= (0.62 + 0.38 * vis)

    # ------------------------------------------------ vertex colour
    # Colour is a *continuous* field: geology does not stop at a joint.  The
    # per-block value only nudges it, otherwise the face reads as painted tiles.
    def hnoise(a, b, seed):
        v = np.sin(a * 127.1 + b * 311.7 + seed) * 43758.5453
        return v - np.floor(v)

    warm = np.array([1.09, 1.01, 0.88])
    cool = np.array([0.91, 0.97, 1.09])
    huefield = vn(X, Y, 0.85, 21) * 0.65 + 0.35 * (vn(X, Y, 0.30, 22) * 0.5 + 0.5)
    huefield = huefield + 0.10 * blk_hue + 0.05 * bed_hue[lay]
    mixw = np.clip(huefield, 0, 1)[..., None]
    tint = cool * (1 - mixw) + warm * mixw

    # value: broad patches (40-150 cm) + a gentle per-block nudge
    val = 0.58 + 0.46 * vn(X, Y, 0.85, 23) + 0.18 * (vn(X, Y, 0.26, 27) - 0.5) + 0.05 * (blk_val - 1.0)
    tint *= val[..., None]

    # darker, slightly cooler where water runs down the face
    wet = np.clip((vn(X, Y * 0.35, 0.55, 24) - 0.52) * 2.4, 0, 1)
    wet *= np.clip(1.15 - Y / H, 0, 1)
    tint *= (1.0 - 0.26 * wet)[..., None]
    tint *= np.array([0.94, 0.97, 1.02])[None, None, :] ** wet[..., None]

    # lichen: patchy crusts, mostly in the upper half and in the hollows
    lich = np.clip((vn(X * 0.8, Y * 0.8, 0.28, 25) - 0.58) * 3.4, 0, 1)
    lich *= np.clip((Y - 0.7) / 2.0, 0, 1) * 0.8
    lich *= np.clip(ao * 1.4, 0, 1)
    tint = tint * (1 - 0.45 * lich[..., None]) + np.array([0.56, 0.66, 0.40]) * 0.45 * lich[..., None]

    # pale dust settles on the upward-facing ledges, matte and desaturated
    up_f = np.clip(n[..., 1], 0, 1) ** 1.3
    tint = tint * (1 - 0.18 * up_f[..., None]) + np.array([0.62, 0.61, 0.59]) * 0.18 * up_f[..., None]

    # 10-40 cm patches: this is the scale that the 1 m camera actually sees
    tint *= (0.86 + 0.30 * vn(X, Y, 0.22, 28))[..., None]
    tint *= (0.92 + 0.16 * vn(X, Y, 0.11, 29))[..., None]

    # damp seep running down the hero window, and a lichen crust beside it
    seep2 = np.exp(-((X + 0.34 + 0.05 * np.sin(Y * 7.0)) / 0.075) ** 2)
    seep2 *= np.clip((2.05 - Y) / 0.5, 0, 1) * np.clip((Y - 0.35) / 0.4, 0, 1)
    tint *= (1.0 - 0.34 * seep2)[..., None]
    tint *= np.array([0.92, 0.96, 1.02])[None, None, :] ** seep2[..., None]
    lich2 = np.exp(-(((X - 0.30) / 0.10) ** 2 + ((Y - 1.34) / 0.085) ** 2))
    lich2 = np.clip(lich2 * 1.6 - 0.25, 0, 1) * (0.6 + 0.4 * vn(X, Y, 0.035, 30))
    tint = tint * (1 - 0.55 * lich2[..., None]) + np.array([0.50, 0.60, 0.34]) * 0.55 * lich2[..., None]

    tint *= (0.80 + 0.24 * ao)[..., None]

    base_rough = np.clip(blk_rough + 0.10 * (vn(X, Y, 0.9, 26) - 0.5) + 0.14 * up_f
                         - 0.12 * lich - 0.30 * wet, 0.25, 0.95)

    col = np.clip(tint * ao[..., None], 0, 2.0)
    roughness = base_rough

    # ------------------------------------------------ write mesh
    verts = np.stack([X, Y, z], -1).astype(np.float32)
    nrm = n.astype(np.float32)
    rgba = np.concatenate([col, roughness[..., None]], -1).astype(np.float32)
    idx = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            a = j * nx + i
            b = a + 1
            c = a + nx
            d = c + 1
            idx.append((a, b, c))
            idx.append((b, d, c))
    idx = np.array(idx, dtype=np.uint32)

    path = os.path.join(OUT_MESH, "rock_face.bin")
    with open(path, "wb") as f:
        f.write(b"RFM2")
        f.write(struct.pack("<iiii", verts.size // 3, idx.size, nx, ny))
        f.write(verts.tobytes())
        f.write(nrm.tobytes())
        f.write(rgba.tobytes())
        f.write(idx.tobytes())
    print("[face] %s  %d verts  %d tris  %.1f MB"
          % (path, verts.size // 3, idx.size // 3, os.path.getsize(path) / 1e6))

    # debug previews (not shipped to the game)
    pv = norm01(z)
    Image.fromarray((pv * 255).astype(np.uint8), "L").save("/tmp/rock_face_heightfield.png")
    return dict(nx=nx, ny=ny)


def preview_mesh():
    """Flat-shaded preview of the baked face so we can eyeball the structure."""
    path = os.path.join(OUT_MESH, "rock_face.bin")
    with open(path, "rb") as f:
        assert f.read(4) == b"RFM1"
        nv, ni = struct.unpack("<ii", f.read(8))
        v = np.frombuffer(f.read(nv * 12), "<f4").reshape(-1, 3)
        n = np.frombuffer(f.read(nv * 12), "<f4").reshape(-1, 3)
        c = np.frombuffer(f.read(nv * 16), "<f4").reshape(-1, 4)
        idx = np.frombuffer(f.read(ni * 4), "<u4").reshape(-1, 3)
    # orthographic render, light from upper-left
    Wpx, Hpx = 1400, 1000
    sx = Wpx / (v[:, 0].max() - v[:, 0].min())
    sy = Hpx / (v[:, 1].max() - v[:, 1].min())
    px = ((v[:, 0] - v[:, 0].min()) * sx).astype(np.int32)
    py = ((v[:, 1].max() - v[:, 1]) * sy * (sy / sx) if abs(sy - sx) < 1e-6
          else (v[:, 1].max() - v[:, 1]) * sy).astype(np.int32)
    py = np.clip(py, 0, Hpx - 1)
    img = np.zeros((Hpx, Wpx, 3), np.float32)
    zbuf = np.full((Hpx, Wpx), -1e9, np.float32)
    L = np.array([-0.45, 0.55, 0.70]); L /= np.linalg.norm(L)
    for t in range(0, len(idx), 1):
        a, b, cc = idx[t]
        tri = np.array([px[a], px[b], px[cc]])
        try_ = np.array([py[a], py[b], py[cc]])
        zz = (v[a, 2], v[b, 2], v[cc, 2])
        shade = np.clip(n[a] @ L, 0, 1) * 0.5 + np.clip(n[b] @ L, 0, 1) * 0.25 + np.clip(n[cc] @ L, 0, 1) * 0.25
        colr = (c[a, :3] * 0.5 + c[b, :3] * 0.25 + c[cc, :3] * 0.25)
        x0, x1 = int(tri.min()), int(tri.max())
        y0, y1 = int(try_.min()), int(try_.max())
        if x1 - x0 > 60 or y1 - y0 > 60:
            continue
        for yy in range(y0, y1 + 1):
            for xx in range(x0, x1 + 1):
                x1a, y1a = tri[0], try_[0]
                x2a, y2a = tri[1], try_[1]
                x3a, y3a = tri[2], try_[2]
                d = (y2a - y3a) * (x1a - x3a) + (x3a - x2a) * (y1a - y3a)
                if abs(d) < 1e-9:
                    continue
                l1 = ((y2a - y3a) * (xx - x3a) + (x3a - x2a) * (yy - y3a)) / d
                l2 = ((y3a - y1a) * (xx - x3a) + (x1a - x3a) * (yy - y3a)) / d
                l3 = 1 - l1 - l2
                if l1 < 0 or l2 < 0 or l3 < 0:
                    continue
                zval = l1 * zz[0] + l2 * zz[1] + l3 * zz[2]
                if zval > zbuf[yy, xx]:
                    zbuf[yy, xx] = zval
                    img[yy, xx] = colr * (0.25 + 0.95 * shade)
    img = np.clip(img, 0, 1) ** (1 / 2.2)
    Image.fromarray((img * 255).astype(np.uint8), "RGB").save("/tmp/rock_face_preview.png")
    print("[face] preview -> /tmp/rock_face_preview.png")


if __name__ == "__main__":
    args = set(sys.argv[1:])
    if not args or "--tex" in args:
        make_face_textures()
        make_struct_textures()
    if not args or "--mesh" in args:
        build_height()
    if "--preview" in args:
        preview_mesh()