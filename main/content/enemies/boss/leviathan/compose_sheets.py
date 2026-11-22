#!/usr/bin/env python3
"""Compose labelled contact sheets from renders/shots/* for visual review."""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders")
SHOTS = os.path.join(ROOT, "shots")
OUT = os.path.join(ROOT, "sheets")
os.makedirs(OUT, exist_ok=True)

FONT = None
for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
          "/usr/share/fonts/TTF/DejaVuSans.ttf"]:
    if os.path.exists(p):
        FONT = ImageFont.truetype(p, 18)
        break
if FONT is None:
    FONT = ImageFont.load_default()


def seq(name, cols=5, tw=340):
    d = os.path.join(SHOTS, name)
    if not os.path.isdir(d):
        print("skip", name)
        return
    files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    if not files:
        return
    ims = [Image.open(os.path.join(d, f)).convert("RGB") for f in files]
    th = int(tw * ims[0].height / ims[0].width)
    rows = (len(ims) + cols - 1) // cols
    pad = 6
    lab = 24
    sheet = Image.new("RGB", (cols * (tw + pad) + pad,
                              rows * (th + lab + pad) + pad), (10, 12, 18))
    dr = ImageDraw.Draw(sheet)
    for i, (im, f) in enumerate(zip(ims, files)):
        r, c = divmod(i, cols)
        x = pad + c * (tw + pad)
        y = pad + r * (th + lab + pad)
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, y + lab))
        dr.text((x + 2, y + 2), os.path.splitext(f)[0], fill=(255, 190, 120), font=FONT)
    p = os.path.join(OUT, name + ".png")
    sheet.save(p)
    print(p, sheet.size)


def stills():
    picks = [
        ("phase1/hero.png", "PHASE 1 / HERO"),
        ("phase1/front.png", "PHASE 1 / FRONT"),
        ("phase1/eye.png", "PHASE 1 / OPTIC"),
        ("phase1/side.png", "PHASE 1 / SIDE"),
        ("phase2/hero.png", "PHASE 2 / HERO"),
        ("phase2/core.png", "PHASE 2 / CORE"),
        ("phase2/front.png", "PHASE 2 / FRONT"),
        ("phase2/side.png", "PHASE 2 / SIDE"),
        ("phase2/back.png", "PHASE 2 / BACK"),
        ("laser/06.png", "LASER / FIRE"),
        ("attack1/07.png", "ATTACK 1 / IMPACT"),
        ("attack2/16.png", "ATTACK 2 / IMPACT"),
        ("attack3/14.png", "ATTACK 3 / SWEEP"),
        ("phase2_open/12.png", "SHELL / OPENING"),
        ("idle_top/10.png", "IDLE / TOP CLEARANCE"),
        ("support_feet/05.png", "SUPPORT / FOOT CONTACT"),
    ]
    tw, th = 500, 281
    cols = 4
    rows = (len(picks) + cols - 1) // cols
    pad = 8
    lab = 26
    sheet = Image.new("RGB", (cols * (tw + pad) + pad,
                              rows * (th + lab + pad) + pad), (10, 12, 18))
    dr = ImageDraw.Draw(sheet)
    for i, (rel, label) in enumerate(picks):
        p = os.path.join(SHOTS, rel)
        if not os.path.exists(p):
            continue
        r, c = divmod(i, cols)
        x = pad + c * (tw + pad)
        y = pad + r * (th + lab + pad)
        im = Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS)
        sheet.paste(im, (x, y + lab))
        dr.text((x + 2, y + 3), label, fill=(255, 190, 120), font=FONT)
    out = os.path.join(OUT, "heroes.png")
    sheet.save(out)
    print(out, sheet.size)


for name, cols in [("idle", 5), ("idle_top", 5), ("support", 5), ("support_side", 5), ("support_feet", 5),
                   ("attack1", 6), ("attack2", 6), ("attack3", 6),
                   ("phase2_open", 6), ("laser", 7)]:
    seq(name, cols)
stills()