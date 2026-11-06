#!/usr/bin/env python3
"""DEEPFALL Phase 5 asset prep — staged assets ONLY, game-tree copies only.

Reads ONLY from ~/workspace/asset-pipeline/staging/deepfall/ (never writes there).
Writes ONLY under ~/workspace/goals/game-off-2026-entry/deepfall-game/assets/
  enemies/<slug>/{walk,attack}_N.png + idle.png
  enemies/MANIFEST.md
  player_anim/melee_0..3.png
  effects/death_0..3.png

Method (matches existing player_anim convention in build_assets.py):
  - frames are cropped to their alpha content bbox, scaled with NEAREST
    (pixel-art sources; LANCZOS was compared and softens the pixel read),
    pasted bottom-centre on a common canvas per enemy.
  - per enemy, EACH animation set is scaled so that set's tallest frame is
    256px tall. Walk/attack/idle renders come at different source scales
    (attack renders are ~600-800px tall, walk ~160-260px); a single scale
    per enemy would make walk frames ~80px tall next to a 256px attack.
    Per-set height normalisation keeps the creature the same on-screen size
    in every animation. Common canvas per enemy: max scaled width x 256.
  - idle.png is the single-pose sprite from enemies/mines/full/, trimmed
    to content bbox and scaled so it is 256px tall (same height as walk/
    attack), pasted bottom-centre on the same common canvas.

Contamination handling (verified visually + by connected-component analysis):
  - mines-walk-v2 on disk holds ONLY bat, ghoul, golem, spider (4 frames
    each). Its raw composite's bottom mimic+worm band was deleted as
    mislabelled in history and is NOT re-sliced from the raw file.
  - mines-walk (v1) spider/mimic/worm frames carry bleed from the enemy
    row above in the source composite (spider legs over the mimic row,
    mimic-chest rim over the worm row). The bleed is disconnected from the
    creature by a transparent gap, so it is removed with a top crop:
    mimic walk crop y=67 (bleed ends <=66, chest starts >=69),
    worm walk crop y=53 (bleed ends <=51, worm starts >=58).
  - tunnel-worm v1 walk frames 1-2 are NOT shippable as an in-place cycle:
    the worm is longer than the frame and each of those frames shows the
    head piece and the tail piece as two disconnected components with a
    ~100px transparent gap between them (the middle of the body is off
    frame). Cycling them would read as the creature splitting apart.
    Only frames 0 and 3 (clean full worms, different undulation poses)
    are shipped as walk_0/walk_1. Reported as a partial set in MANIFEST.md.
  - cave-spider-attack-v2 is partial (frames 1-2 only) and is NOT used;
    cave-spider-attack-redo (4 frames) is used instead.
  - ore-mimic-attack-v2 is 3 frames only; shipped as-is, no 4th invented.

Player melee (tech-melee-v2, 4 frames):
  - the 256x195 canvas at 0.5 scale does NOT fit: frame 1 is 1031px wide
    (blade lunge), i.e. 516px at 0.5. Instead the set is scaled so the
    tallest frame is 195px tall (matching the existing player_anim canvas
    height; body then measures ~182px vs idle's ~190px) and pasted
    bottom-centre on a common 317x195 canvas. Feet sit at the canvas
    bottom, so Phase 5 code can anchor it like the other player anims:
    with Sprite2D scale 0.5, sprite y = 40 - 195*0.5/2 = -8.75 (same as
    the existing idle/walk/shoot frames).

Death effect:
  - smoke-puff.gif (4 frames, 128x128, transparent) is the generic poof;
    spore-puff (green), ember-burst (orange) and void-implosion (purple)
    are element/themed and not generic. Frames grow but never dissipate,
    so Phase 5 code should fade the sprite's modulate alpha to 0 over
    the effect's lifetime (code fade, no fabricated frames).
"""
import os
from PIL import Image

STAGE = os.path.expanduser("~/workspace/asset-pipeline/staging/deepfall")
GAME = os.path.expanduser("~/workspace/goals/game-off-2026-entry/deepfall-game")
MF = os.path.join(STAGE, "multiframe")
FULL = os.path.join(STAGE, "enemies", "mines", "full")

ENEMIES = {
    # slug: (walk_dir, walk_source_frames, walk_top_crop, attack_dir, attack_frames)
    "cave-bat-swarm": ("mines-walk-v2", [0, 1, 2, 3], 0, "cave-bat-swarm-attack-v2", 4),
    "miner-ghoul":    ("mines-walk-v2", [0, 1, 2, 3], 0, "miner-ghoul-attack-v2", 4),
    "rock-golem":     ("mines-walk-v2", [0, 1, 2, 3], 0, "rock-golem-attack-v2", 4),
    "cave-spider":    ("mines-walk-v2", [0, 1, 2, 3], 0, "cave-spider-attack-redo", 4),
    "ore-mimic":      ("mines-walk",    [0, 1, 2, 3], 67, "ore-mimic-attack-v2", 3),
    "tunnel-worm":    ("mines-walk",    [0, 3],       53, "tunnel-worm-attack-v2", 4),
}
TARGET_H = 256


def load(path):
    return Image.open(path).convert("RGBA")


def content_crop(im):
    bb = im.getchannel("A").getbbox()
    assert bb, "fully transparent frame"
    return im.crop(bb)


def process_set(frames):
    """frames: list of RGBA images (already top-cropped / content-ready).
    Returns list of scaled RGBA images, each cropped to content bbox,
    scaled so the tallest frame in the set is TARGET_H tall."""
    cropped = [content_crop(f) for f in frames]
    max_h = max(f.height for f in cropped)
    scale = TARGET_H / max_h
    out = []
    for f in cropped:
        nw = max(1, round(f.width * scale))
        nh = max(1, round(f.height * scale))
        out.append(f.resize((nw, nh), Image.NEAREST))
    return out, scale


def main():
    report = {}
    for slug, (walk_dir, walk_idx, top_crop, atk_dir, atk_n) in ENEMIES.items():
        outdir = os.path.join(GAME, "assets", "enemies", slug)
        os.makedirs(outdir, exist_ok=True)
        # --- walk ---
        walk_frames = []
        for i in walk_idx:
            p = os.path.join(MF, walk_dir, f"{slug}-{i}.png")
            im = load(p)
            if top_crop:
                im = im.crop((0, top_crop, im.width, im.height))
            walk_frames.append(im)
        walk_scaled, walk_scale = process_set(walk_frames)
        # --- attack ---
        atk_frames = [load(os.path.join(MF, atk_dir, f"{slug}-{i}.png"))
                      for i in range(atk_n)]
        atk_scaled, atk_scale = process_set(atk_frames)
        # --- idle ---
        idle_scaled, idle_scale = process_set([load(os.path.join(FULL, f"{slug}.png"))])
        # --- common canvas ---
        all_frames = walk_scaled + atk_scaled + idle_scaled
        cw = max(f.width for f in all_frames)
        ch = TARGET_H
        assert all(f.height <= ch for f in all_frames), slug
        def paste(frames, prefix):
            for n, f in enumerate(frames):
                cv = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
                cv.paste(f, ((cw - f.width) // 2, ch - f.height), f)
                cv.save(os.path.join(outdir, f"{prefix}_{n}.png"))
        paste(walk_scaled, "walk")
        paste(atk_scaled, "attack")
        idle = idle_scaled[0]
        cv = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        cv.paste(idle, ((cw - idle.width) // 2, ch - idle.height), idle)
        cv.save(os.path.join(outdir, "idle.png"))
        report[slug] = dict(
            canvas=(cw, ch), walk=len(walk_scaled), walk_src=walk_idx,
            walk_scale=round(walk_scale, 4), attack=len(atk_scaled),
            atk_scale=round(atk_scale, 4), idle_scale=round(idle_scale, 4),
            walk_dir=walk_dir, atk_dir=atk_dir, top_crop=top_crop,
        )
        print(slug, "canvas", (cw, ch), "walk", len(walk_scaled),
              "attack", len(atk_scaled), "scales w/a/i",
              round(walk_scale, 3), round(atk_scale, 3), round(idle_scale, 3))

    # --- player melee: tallest frame -> 195px (existing player canvas height) ---
    melee_src = [load(os.path.join(MF, "tech-melee-v2", f"tech-soldier-{i}.png"))
                 for i in range(4)]
    melee_cropped = [content_crop(f) for f in melee_src]
    mscale = 195 / max(f.height for f in melee_cropped)
    melee_scaled = []
    for f in melee_cropped:
        melee_scaled.append(f.resize((max(1, round(f.width * mscale)),
                                      max(1, round(f.height * mscale))), Image.NEAREST))
    mcw = max(f.width for f in melee_scaled)
    mch = max(f.height for f in melee_scaled)
    assert mch == 195, mch
    for n, f in enumerate(melee_scaled):
        cv = Image.new("RGBA", (mcw, mch), (0, 0, 0, 0))
        cv.paste(f, ((mcw - f.width) // 2, mch - f.height), f)
        cv.save(os.path.join(GAME, "assets", "player_anim", f"melee_{n}.png"))
    print("melee canvas", (mcw, mch), "scale", round(mscale, 4))

    # --- death effect: smoke-puff.gif frames, native 128x128 ---
    gif = Image.open(os.path.join(STAGE, "effects", "smoke-puff.gif"))
    fxdir = os.path.join(GAME, "assets", "effects")
    os.makedirs(fxdir, exist_ok=True)
    canvas = Image.new("RGBA", gif.size, (0, 0, 0, 0))
    n_fx = 0
    for i in range(getattr(gif, "n_frames", 1)):
        gif.seek(i)
        frame = gif.convert("RGBA")
        canvas.paste(frame, (0, 0), frame)
        canvas.copy().save(os.path.join(fxdir, f"death_{i}.png"))
        n_fx += 1
    print("death frames", n_fx, "size", gif.size)

    return report, (mcw, mch, round(mscale, 4)), n_fx


if __name__ == "__main__":
    main()
