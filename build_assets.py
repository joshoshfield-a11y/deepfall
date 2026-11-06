#!/usr/bin/env python3
"""Phase 2 asset prep: clean staged 64px tiles into 4 deterministic variants,
build edge/corner/damage overlays, slice tech-soldier strips onto a common
bottom-centre canvas. No AI images; PIL only. Run from the project root."""
import os, random
from PIL import Image, ImageDraw, ImageEnhance

ROOT = os.path.dirname(os.path.abspath(__file__))
STAGED = os.path.expanduser("~/workspace/asset-pipeline/staging/deepfall/tiles-real/terraria-blocks/64")
ANIM = os.path.expanduser("~/workspace/asset-pipeline/staging/deepfall/animations")
OUT = os.path.join(ROOT, "assets")
os.makedirs(os.path.join(OUT, "tiles2"), exist_ok=True)
os.makedirs(os.path.join(OUT, "player_anim"), exist_ok=True)

NAMES = ["dirt", "grass-dirt", "stone", "gold-ore", "amber-ore", "wood",
         "wood-platform", "brick", "mossy-stone", "cracked-stone", "sand",
         "obsidian", "dirt-wall", "cave-wall-dark"]
STRIP_TILES = {"stone", "gold-ore", "amber-ore"}  # bottom mini-tile strip

def clean(name, im):
    im = im.convert("RGBA")
    # 1. ore mini-tile strip: overwrite bottom 8 rows with the band above
    if name in STRIP_TILES:
        band = im.crop((0, 48, 64, 56))
        im.paste(band, (0, 56))
    # 2. white sky corners (grass-dirt): near-white -> dirt brown
    if name == "grass-dirt":
        px = im.load()
        for y in range(16):
            for x in range(64):
                r, g, b, a = px[x, y]
                if r > 235 and g > 235 and b > 235:
                    px[x, y] = (80, 51, 36, 255)
    # 3. soften the hard dark panel border: blend outer 2px toward pixel 3px in
    px = im.load()
    for i in range(64):
        for edge in range(2):
            for a, b in ((edge, 3), (63 - edge, 60)):
                r1, g1, b1, _ = px[b, i] if edge < 2 and a == edge else px[i, b]
                # handled per-axis below; placeholder replaced by direct ops
                pass
    # do it explicitly per axis
    for i in range(64):
        for x in (0, 1, 62, 63):
            src = 3 if x < 32 else 60
            r, g, b, al = px[x, i]; r2, g2, b2, _ = px[src, i]
            px[x, i] = ((r + r2) // 2, (g + g2) // 2, (b + b2) // 2, al)
        for y in (0, 1, 62, 63):
            src = 3 if y < 32 else 60
            r, g, b, al = px[i, y]; r2, g2, b2, _ = px[i, src]
            px[i, y] = ((r + r2) // 2, (g + g2) // 2, (b + b2) // 2, al)
    return im

for name in NAMES:
    base = clean(name, Image.open(os.path.join(STAGED, name + ".png")))
    variants = [base, base.transpose(Image.FLIP_LEFT_RIGHT),
                base.transpose(Image.FLIP_TOP_BOTTOM),
                ImageEnhance.Brightness(base.transpose(Image.FLIP_LEFT_RIGHT)
                                        .transpose(Image.FLIP_TOP_BOTTOM)).enhance(0.94)]
    for vi, v in enumerate(variants):
        v.save(os.path.join(OUT, "tiles2", f"{name}_v{vi}.png"))

# --- edge / corner / damage overlays (transparent, dark crevice) ---
def overlay_edge(side):
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rng = random.Random(hash(side) & 0xFFFF)
    # jagged band along the edge, 5-10px deep
    pts = []
    if side == "top":
        pts = [(x, rng.randint(4, 10)) for x in range(0, 65, 8)]
        d.polygon([(0, 0)] + pts + [(64, 0)], fill=(30, 30, 38, 210))
    elif side == "bottom":
        pts = [(x, 64 - rng.randint(4, 10)) for x in range(0, 65, 8)]
        d.polygon([(0, 64)] + pts + [(64, 64)], fill=(30, 30, 38, 210))
    elif side == "left":
        pts = [(rng.randint(4, 10), y) for y in range(0, 65, 8)]
        d.polygon([(0, 0)] + pts + [(0, 64)], fill=(30, 30, 38, 210))
    elif side == "right":
        pts = [(64 - rng.randint(4, 10), y) for y in range(0, 65, 8)]
        d.polygon([(64, 0)] + pts + [(64, 64)], fill=(30, 30, 38, 210))
    return im

def overlay_corner(name):
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # L-shape: two 8px bands meeting at the corner
    if name == "tl":
        d.rectangle([0, 0, 64, 8], fill=(30, 30, 38, 210)); d.rectangle([0, 0, 8, 64], fill=(30, 30, 38, 210))
    elif name == "tr":
        d.rectangle([0, 0, 64, 8], fill=(30, 30, 38, 210)); d.rectangle([56, 0, 64, 64], fill=(30, 30, 38, 210))
    elif name == "bl":
        d.rectangle([0, 56, 64, 64], fill=(30, 30, 38, 210)); d.rectangle([0, 0, 8, 64], fill=(30, 30, 38, 210))
    elif name == "br":
        d.rectangle([0, 56, 64, 64], fill=(30, 30, 38, 210)); d.rectangle([56, 0, 64, 64], fill=(30, 30, 38, 210))
    return im

for s in ("top", "bottom", "left", "right"):
    overlay_edge(s).save(os.path.join(OUT, f"edge_{s}.png"))
for c in ("tl", "tr", "bl", "br"):
    overlay_corner(c).save(os.path.join(OUT, f"corner_{c}.png"))

# damage overlay: dark crack polylines
dmg = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(dmg)
rng = random.Random(20261101)
for _ in range(5):
    x, y = rng.randint(8, 56), rng.randint(8, 56)
    pts = [(x, y)]
    for _ in range(4):
        x += rng.randint(-12, 12); y += rng.randint(-12, 12); pts.append((x, y))
    d.line(pts, fill=(20, 20, 26, 230), width=2)
dmg.save(os.path.join(OUT, "damage.png"))

# --- player animation frames, bottom-centre on a common 128x195 canvas ---
BANDS = {
    "idle": [(2, 123), (139, 236), (266, 362), (392, 489), (506, 627), (632, 753), (770, 866), (886, 1003), (1020, 1118)],
    "walk": [(6, 103), (119, 209), (222, 327), (341, 428), (445, 544), (559, 648), (668, 761), (780, 867), (882, 986)],
    "shoot": [(2, 120), (130, 249), (272, 363), (394, 498), (516, 636)],
}
for anim, bands in BANDS.items():
    strip = Image.open(os.path.join(ANIM, f"tech-soldier-{anim}-strip.png")).convert("RGBA")
    for i, (x0, x1) in enumerate(bands):
        frame = strip.crop((x0, 0, x1 + 1, strip.height))
        canvas = Image.new("RGBA", (128, 195), (0, 0, 0, 0))
        canvas.paste(frame, ((128 - frame.width) // 2, 195 - frame.height), frame)
        canvas.save(os.path.join(OUT, "player_anim", f"{anim}_{i}.png"))
        print(anim, i, frame.size)

# torch art copy
import shutil
shutil.copy(os.path.expanduser("~/workspace/asset-pipeline/staging/deepfall/items/torch.png"),
            os.path.join(OUT, "torch.png"))
print("tiles variants + overlays + player frames done")
