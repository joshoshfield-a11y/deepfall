#!/usr/bin/env python3
"""Phase 10 walk-cycle fix: rescale each class's walkcycle frames so the
figure height matches that class's idle figure height EXACTLY, feet anchored
at the idle feet line, figure centred on the canvas.

Root cause (measured 2026-11-05): the walkcycle sheets were generated as a
separate sheet at a different figure scale than the idle/shoot strips:
  tech idle body h~189 vs walkcycle bodies 173-195, feet bottoms 180-194
  red  idle body h~189 vs walkcycle bodies 195 (full canvas height)
  mage idle body h~104 vs walkcycle bodies 195  (walk was ~1.9x idle!)
All 4 walk frames per class ARE true side views (verified on contact
sheets), so none are dropped — only rescaled/re-anchored.

Method: largest connected component of the alpha mask = the figure.
scale = idle_body_h / body_h; rigid scale of the whole frame about (0,0),
then translate so the figure's bottom == idle figure bottom and the
figure's centre-x == canvas centre (128). Originals are backed up to
assets/player_anim/walkcycle_orig/<class>/ before overwriting.
No frames are redrawn or regenerated.
"""
import os
import shutil
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
ANIM = os.path.join(ROOT, "assets", "player_anim")
CLASSES = {"tech": "", "red": "red", "mage": "mage"}


def main_body_bbox(im):
    """Largest connected component of the alpha mask = the figure torso.
    Walkcycle frames split the figure across components (extended limbs,
    raised weapons detach by a few px), so height/bottom come from the
    UNION of all significant components (>=200 px), while centre-x comes
    from the largest component (the torso — the visual anchor)."""
    a = np.array(im.convert("RGBA"))[:, :, 3] > 20
    H, W = a.shape
    seen = np.zeros_like(a, dtype=bool)
    comps = []
    for y in range(H):
        for x in range(W):
            if a[y, x] and not seen[y, x]:
                q = deque([(y, x)])
                seen[y, x] = True
                minx = maxx = x
                miny = maxy = y
                n = 0
                while q:
                    cy, cx = q.popleft()
                    n += 1
                    minx = min(minx, cx); maxx = max(maxx, cx)
                    miny = min(miny, cy); maxy = max(maxy, cy)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and a[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
                comps.append((n, minx, maxx, miny, maxy))
    comps.sort(reverse=True)
    big = [c for c in comps if c[0] >= 200]
    if not big:
        big = comps[:1]
    ux0 = min(c[1] for c in big); ux1 = max(c[2] for c in big)
    uy0 = min(c[3] for c in big); uy1 = max(c[4] for c in big)
    # Return (px, union_x0, union_x1, union_y0, union_y1, torso_cx).
    torso = comps[0]
    return (torso[0], ux0, ux1, uy0, uy1, (torso[1] + torso[2]) / 2.0)


def main():
    print("Phase 10 walk-cycle rescale (idle-height match, feet anchored)")
    for cls, sub in CLASSES.items():
        base = os.path.join(ANIM, sub) if sub else ANIM
        backup = os.path.join(ANIM, "walkcycle_orig", cls)
        os.makedirs(backup, exist_ok=True)
        # Idle reference: mean body height + mean body bottom over idle frames.
        ihs, ibs = [], []
        for f in sorted(os.listdir(base)):
            if f.startswith("idle_") and f.endswith(".png"):
                b = main_body_bbox(Image.open(os.path.join(base, f)))
                ihs.append(b[4] - b[3] + 1)
                ibs.append(b[4])
        idle_h = sum(ihs) / len(ihs)
        idle_bottom = int(round(sum(ibs) / len(ibs)))
        print(f"{cls}: idle body h mean={idle_h:.1f} bottom={idle_bottom} "
              f"(n={len(ihs)}, range {min(ihs)}-{max(ihs)})")
        for i in range(4):
            name = f"walkcycle_{i}.png"
            path = os.path.join(base, name)
            # Restore the original first (idempotent re-runs).
            bk = os.path.join(backup, name)
            if os.path.exists(bk):
                shutil.copy2(bk, path)
            im = Image.open(path).convert("RGBA")
            b = main_body_bbox(im)
            bh = b[4] - b[3] + 1
            bcx = b[5]
            s = idle_h / bh
            # Scale whole frame about origin (EXACT factor s — no padding
            # fudge, or the effective scale drifts), then translate so
            # the figure bottom == idle bottom and torso centre == 128.
            W, H = im.size
            big = im.resize((int(round(W * s)), int(round(H * s))), Image.LANCZOS)
            tx = int(round(128 - bcx * s))
            ty = int(round(idle_bottom - (b[4] + 1) * s))
            # Paste via an oversized canvas so negative / overflowing
            # offsets clip cleanly instead of raising.
            tmp = Image.new("RGBA", (W + 16, H + 16), (0, 0, 0, 0))
            tmp.alpha_composite(big, (tx + 8, ty + 8))
            out = tmp.crop((8, 8, 8 + W, 8 + H))
            # Backup original once.
            bk = os.path.join(backup, name)
            if not os.path.exists(bk):
                shutil.copy2(path, bk)
            out.save(path)
            nb = main_body_bbox(out)
            print(f"  {name}: body h {bh} -> {nb[4]-nb[3]+1} "
                  f"(scale {s:.3f}) bottom {b[4]} -> {nb[4]} "
                  f"(target {idle_bottom}) torso-x {bcx:.0f} -> "
                  f"{nb[5]:.0f} (target 128)")
    print("done — originals in assets/player_anim/walkcycle_orig/<class>/")


if __name__ == "__main__":
    main()
