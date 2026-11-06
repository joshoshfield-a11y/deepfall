#!/usr/bin/env python3
"""Phase 9 asset prep (DEEPFALL polish pass). No AI images; PIL only, staged sources copied, never moved.

1. Tech soldier missing sets (same canvases Phase 8 uses):
   - dying 6: cleaned-regen/tech-soldier r4c3..c8 (r4c0..c2 are raw icons, skipped — same rule as red)
   - thruster 6: cleaned-regen/tech-soldier r3c0..c5
   - crouch 4: multiframe/crouch/tech-soldier-crouch-0..3.png (clean separate
     PNGs — the tech-crouch-v2 GIF's frames ghost when naively extracted, so the
     GIF is NOT used as a source)
   -> assets/player_anim/{dying,thruster}_0..5.png (128x195),
      assets/player_anim/crouch_0..3.png (256x195)
2. True transition / outer-corner tiles, generated procedurally from the staged
   atlas fills (rock_0 / dirt_0, assets/atlas3/):
   - trans_rock_N/E/S/W: rock fill with a jagged dirt intrusion from that side
   - trans_dirt_N/E/S/W: dirt fill with a jagged rock intrusion from that side
   - corner_rock_TL/TR/BL/BR, corner_dirt_TL/TR/BL/BR: fill with the outer
     corner quarter cut to dark cave colour with a jagged edge
   -> assets/tiles2/{trans,corner}_*_v0.png (64x64, single variant each)
   These are REAL tile art selected by neighbour mask in main.gd — they replace
   the dark overlay wedges on transition/corner cells. Straight-edge cells keep
   the overlay (it is the silhouette breaker there).
3. Mage orb impact: frost-burst.gif frames 0..2 (staged effects, transparent,
   blue — matches the cyan orb) -> assets/effects/orb_impact_0..2.png
Run from the project root.
"""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
STAGED = os.path.expanduser("~/workspace/asset-pipeline/staging/deepfall")
OUT = os.path.join(ROOT, "assets", "player_anim")
TILES2 = os.path.join(ROOT, "assets", "tiles2")
EFFECTS = os.path.join(ROOT, "assets", "effects")

CANVAS_SMALL = (128, 195)
CANVAS_BIG = (256, 195)


def paste_fit(frame: Image.Image, canvas_size: tuple) -> Image.Image:
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    w, h = frame.size
    scale = min(canvas_size[0] / w, canvas_size[1] / h, 1.0)
    if scale < 1.0:
        frame = frame.resize((max(1, int(w * scale)), max(1, int(h * scale))),
                             Image.LANCZOS)
    canvas.paste(frame, ((canvas_size[0] - frame.width) // 2,
                         canvas_size[1] - frame.height), frame)
    return canvas


def save_set(files, out_dir, set_name, canvas):
    os.makedirs(out_dir, exist_ok=True)
    for i, src in enumerate(files):
        im = Image.open(src).convert("RGBA")
        paste_fit(im, canvas).save(os.path.join(out_dir, "%s_%d.png" % (set_name, i)))
    return len(files)


TECH = os.path.join(STAGED, "cleaned-regen", "tech-soldier")
# --- tech dying / thruster (strip sets, small canvas) ---
dying = [os.path.join(TECH, "r4c%d_dying.png" % i) for i in range(3, 9)]
thruster = [os.path.join(TECH, "r3c%d_thruster.png" % i) for i in range(6)]
for f in dying + thruster:
    assert os.path.exists(f), "missing source frame: %s" % f
print("tech dying", save_set(dying, OUT, "dying", CANVAS_SMALL))
print("tech thruster", save_set(thruster, OUT, "thruster", CANVAS_SMALL))

# --- tech crouch (clean separate PNGs, big canvas) ---
crouch = [os.path.join(STAGED, "multiframe", "crouch",
                       "tech-soldier-crouch-%d.png" % i) for i in range(4)]
for f in crouch:
    assert os.path.exists(f), "missing source frame: %s" % f
print("tech crouch", save_set(crouch, OUT, "crouch", CANVAS_BIG))

# --- transition / corner tiles from atlas fills ---
rock = Image.open(os.path.join(ROOT, "assets", "atlas3", "rock_0.png")).convert("RGBA")
dirt = Image.open(os.path.join(ROOT, "assets", "atlas3", "dirt_0.png")).convert("RGBA")
assert rock.size == (64, 64) and dirt.size == (64, 64)


def jag(t: int) -> int:
    # deterministic jagged offset in [-8, +8] per column/row index
    return ((t * 73 + 11) % 17) - 8


def trans_tile(base: Image.Image, intr: Image.Image, side: str) -> Image.Image:
    out = base.copy()
    px_b = base.load()
    px_i = intr.load()
    px_o = out.load()
    for y in range(64):
        for x in range(64):
            if side == "S":
                take = y >= 32 + jag(x)
            elif side == "N":
                take = y < 32 + jag(x)
            elif side == "E":
                take = x >= 32 + jag(y)
            else:  # W
                take = x < 32 + jag(y)
            if take:
                px_o[x, y] = px_i[x, y]
    return out


def corner_tile(base: Image.Image, corner: str) -> Image.Image:
    out = base.copy()
    px_o = out.load()
    for y in range(64):
        for x in range(64):
            if corner == "TL":
                d = x + y
            elif corner == "TR":
                d = (63 - x) + y
            elif corner == "BL":
                d = x + (63 - y)
            else:  # BR
                d = (63 - x) + (63 - y)
            if d < 36 + jag((x + y) % 64):
                n = ((x * 31 + y * 17) % 9) - 4
                px_o[x, y] = (10 + n, 16 + n, 26 + n, 255)
    return out


os.makedirs(TILES2, exist_ok=True)
made = []
for side in ["N", "E", "S", "W"]:
    trans_tile(rock, dirt, side).save(os.path.join(TILES2, "trans_rock_%s_v0.png" % side))
    trans_tile(dirt, rock, side).save(os.path.join(TILES2, "trans_dirt_%s_v0.png" % side))
    made += ["trans_rock_%s" % side, "trans_dirt_%s" % side]
for corner in ["TL", "TR", "BL", "BR"]:
    corner_tile(rock, corner).save(os.path.join(TILES2, "corner_rock_%s_v0.png" % corner))
    corner_tile(dirt, corner).save(os.path.join(TILES2, "corner_dirt_%s_v0.png" % corner))
    made += ["corner_rock_%s" % corner, "corner_dirt_%s" % corner]
print("transition/corner tiles:", len(made), made)

# --- orb impact frames from staged frost-burst ---
os.makedirs(EFFECTS, exist_ok=True)
gif = Image.open(os.path.join(STAGED, "effects", "frost-burst.gif"))
assert gif.n_frames == 3, gif.n_frames
for i in range(3):
    gif.seek(i)
    gif.convert("RGBA").save(os.path.join(EFFECTS, "orb_impact_%d.png" % i))
print("orb impact frames: 3")

# --- manifest: add tech entry ---
mpath = os.path.join(OUT, "MANIFEST.json")
with open(mpath) as f:
    manifest = json.load(f)
manifest["classes"]["tech"] = {
    "idle": 9, "walk": 9, "shoot": 5, "walkcycle": 4, "fall": 3, "melee": 4,
    "reload": 0, "thruster": 6, "dying": 6, "crouch": 4, "climb": 0, "swim": 0,
}
manifest["notes"].append(
    "Phase 9: tech dying (r4c3..c8, 6) + thruster (r3c0..c5, 6) + crouch "
    "(multiframe/crouch clean PNGs, 4) sliced into the flat player_anim root. "
    "Tech reload (r2c5..c8, 4) exists staged but is NOT sliced: no reload "
    "mechanic exists in-game, so reload stays loaded-but-untriggered for "
    "red/mage and absent for tech. Tech climb/swim still absent (no ladder or "
    "water state in-game; climb frames have ladders baked in).")
with open(mpath, "w") as f:
    json.dump(manifest, f, indent=2)
print("MANIFEST updated")
