#!/usr/bin/env python3
"""Phase 8 asset prep: slice red soldier + hooded mage staged frames onto
the same canvases the tech soldier uses (128x195 for strip sets, 256x195
for walkcycle/melee/crouch/climb/swim), bottom-centre. No AI images; PIL only.

Sources:
- cleaned-regen/red-soldier/: r0 idle 9, r1 walk 9, r2 shoot 5 + reload 4,
  r3 thruster 6, r4 dying 6 (r4c3..c8; r4c0..c2 are raw icons, skipped).
- cleaned-regen/mage-fresh/: r0 idle 7, r1 walk 7, r2 shoot 6 (r2c5 is
  BAD/PARTIAL — EXCLUDED, mage shoot is 5 clean frames), r3 reload 7,
  r4 thruster 5, r6 dying 5 (r6c0..c3 + r6c5; r6c4 was dropped at slice
  time and does not exist).
- atlas-art/sliced/{red,mage}-walk-cycle/walk-0..3: 4-frame walk cycles
  (read as 2-pose alternations; used honestly as-is).
- multiframe/{red,mage}-{crouch-v2|crouch-redo,climb-v2,melee-v2,swim-v2}:
  4 frames each. Red swim uses frames 0/1/3 only (frame 2 is front-facing).
  Climb frames have ladders baked in (same as tech's climb situation).
  Mage swim is upright/wading, used as-is.
- No fall/land sets exist for red or mage: NO fall frames are generated.
  In code, airborne reuses thruster frame 0 and land reuses the lowest
  crouch frame (both real frames of that character, documented in README).
Run from the project root.
"""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
STAGED = os.path.expanduser("~/workspace/asset-pipeline/staging/deepfall")
OUT = os.path.join(ROOT, "assets", "player_anim")

CANVAS_SMALL = (128, 195)
CANVAS_BIG = (256, 195)


def paste_fit(frame: Image.Image, canvas_size: tuple) -> Image.Image:
    """Scale frame to fit the canvas (never upscale), paste bottom-centre."""
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    w, h = frame.size
    scale = min(canvas_size[0] / w, canvas_size[1] / h, 1.0)
    if scale < 1.0:
        frame = frame.resize((max(1, int(w * scale)), max(1, int(h * scale))),
                             Image.LANCZOS)
    canvas.paste(frame, ((canvas_size[0] - frame.width) // 2,
                         canvas_size[1] - frame.height), frame)
    return canvas


def save_set(cls: str, set_name: str, files: list, canvas: tuple) -> int:
    d = os.path.join(OUT, cls)
    os.makedirs(d, exist_ok=True)
    for i, src in enumerate(files):
        im = Image.open(src).convert("RGBA")
        paste_fit(im, canvas).save(os.path.join(d, "%s_%d.png" % (set_name, i)))
    return len(files)


def staged(*parts: str) -> str:
    return os.path.join(STAGED, *parts)


manifest = {"classes": {}, "excluded": {}, "notes": []}

# --- strip sets from cleaned-regen ---
RED = staged("cleaned-regen", "red-soldier")
MAGE = staged("cleaned-regen", "mage-fresh")
strip_sets = {
    "red": {
        "idle": ["r0c%d_idle.png" % i for i in range(9)],
        "walk": ["r1c%d_walk.png" % i for i in range(9)],
        "shoot": ["r2c%d_shoot.png" % i for i in range(5)],
        "reload": ["r2c%d_reload.png" % i for i in range(5, 9)],
        "thruster": ["r3c%d_thruster.png" % i for i in range(6)],
        "dying": ["r4c%d_dying.png" % i for i in range(3, 9)],
    },
    "mage": {
        "idle": ["r0c%d_idle.png" % i for i in range(7)],
        "walk": ["r1c%d_walk.png" % i for i in range(7)],
        # shoot: r2c0..c4 only — r2c5_shoot.png is bad/partial, EXCLUDED.
        "shoot": ["r2c%d_shoot.png" % i for i in range(5)],
        "reload": ["r3c%d_reload.png" % i for i in range(7)],
        "thruster": ["r4c%d_thruster.png" % i for i in range(5)],
        # dying: r6c0..c3 + r6c5 (r6c4 does not exist — dropped at slice time).
        "dying": ["r6c0_dying.png", "r6c1_dying.png", "r6c2_dying.png",
                  "r6c3_dying.png", "r6c5_dying.png"],
    },
}
manifest["excluded"]["mage_shoot"] = {
    "file": "cleaned-regen/mage-fresh/r2c5_shoot.png",
    "reason": "bad/partial frame (dark, truncated) — excluded from the "
              "mage shoot animation; mage shoot is the 5 clean frames r2c0..c4",
}
manifest["excluded"]["red_swim_frame2"] = {
    "file": "multiframe/red-swim-v2/red-soldier-2.png",
    "reason": "front-facing star-jump pose; red swim loop uses frames 0/1/3 "
              "for a clean horizontal loop",
}
manifest["notes"].append(
    "No fall/land frames exist for red or mage; code reuses thruster frame 0 "
    "for airborne and the lowest crouch frame for landing (real frames of "
    "that character, not generated). Distinct fall/land poses are still missing.")
manifest["notes"].append(
    "Climb frames have ladders baked in (same caveat as the tech climb set); "
    "no climb state exists in-game yet, so the sets are staged in the game "
    "tree but not driven.")
manifest["notes"].append(
    "Mage swim is upright/wading (never goes horizontal); used as-is. "
    "Red/mage walk cycles read as 2-pose alternations; used as-is.")

for cls, base in (("red", RED), ("mage", MAGE)):
    manifest["classes"][cls] = {}
    for set_name, names in strip_sets[cls].items():
        files = [os.path.join(base, n) for n in names]
        for f in files:
            assert os.path.exists(f), "missing source frame: %s" % f
        n = save_set(cls, set_name, files, CANVAS_SMALL)
        manifest["classes"][cls][set_name] = n
        print(cls, set_name, n)

# --- big-canvas sets: walkcycle, melee, crouch, climb, swim ---
big_sets = {
    "red": {
        "walkcycle": [staged("atlas-art", "sliced", "red-walk-cycle", "walk-%d.png" % i)
                      for i in range(4)],
        "melee": [staged("multiframe", "red-melee-v2", "red-soldier-%d.png" % i)
                  for i in range(4)],
        "crouch": [staged("multiframe", "red-crouch-v2", "red-soldier-%d.png" % i)
                   for i in range(4)],
        "climb": [staged("multiframe", "red-climb-v2", "red-soldier-%d.png" % i)
                  for i in range(4)],
        # swim: frames 0, 1, 3 only — frame 2 is front-facing, excluded.
        "swim": [staged("multiframe", "red-swim-v2", "red-soldier-%d.png" % i)
                 for i in (0, 1, 3)],
    },
    "mage": {
        "walkcycle": [staged("atlas-art", "sliced", "mage-walk-cycle", "walk-%d.png" % i)
                      for i in range(4)],
        "melee": [staged("multiframe", "mage-melee-v2", "mage-fresh-%d.png" % i)
                  for i in range(4)],
        "crouch": [staged("multiframe", "mage-crouch-redo", "mage-fresh-%d.png" % i)
                   for i in range(4)],
        "climb": [staged("multiframe", "mage-climb-v2", "mage-fresh-%d.png" % i)
                  for i in range(4)],
        "swim": [staged("multiframe", "mage-swim-v2", "mage-fresh-%d.png" % i)
                 for i in range(4)],
    },
}
for cls, sets in big_sets.items():
    for set_name, files in sets.items():
        for f in files:
            assert os.path.exists(f), "missing source frame: %s" % f
        n = save_set(cls, set_name, files, CANVAS_BIG)
        manifest["classes"][cls][set_name] = n
        print(cls, set_name, n)

# fall: intentionally absent for red/mage (no source frames exist).
manifest["classes"]["red"]["fall"] = 0
manifest["classes"]["mage"]["fall"] = 0

with open(os.path.join(OUT, "MANIFEST.json"), "w") as f:
    json.dump(manifest, f, indent=2)
print("Phase 8 assets done:", json.dumps(manifest["classes"]))
