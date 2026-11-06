"""build_pixel_enemies.py - DEEPFALL Phase 12 pixel-art cave enemies.

Six enemies redrawn in the same crisp pixel style as the hero
(build_pixel_hero.py): small canvases, flat colours + one highlight
and one shadow tone, auto 1px dark outline, scaled x3 in-game.
Every frame is drawn procedurally from a phase value, so walk and
attack cycles are real distinct animation frames.

Output: assets/enemies_px/<slug>/{idle,walk_N,attack_N}.png
Frame counts match enemy.gd STATS (mimic attack 3, worm walk 2).
Run:  python3 build_pixel_enemies.py
"""
import math
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "assets", "enemies_px")
OUTLINE = (16, 12, 18, 255)


def canvas(w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def outline(im):
    w, h = im.size
    src = im.copy()
    px = src.load()
    out = im.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] != 0 and px[nx, ny] != OUTLINE:
                    out[x, y] = OUTLINE
                    break
    return im


def ell(d, cx, cy, rx, ry, col):
    d.ellipse([round(cx - rx), round(cy - ry), round(cx + rx), round(cy + ry)], fill=col)


def rect(d, x, y, w, h, col):
    d.rectangle([round(x), round(y), round(x + w - 1), round(y + h - 1)], fill=col)


def line(d, a, b, col, w=1):
    d.line([tuple(map(round, a)), tuple(map(round, b))], fill=col, width=w)


# ------------------------------------------------------------------ bat
def bat(kind, i, n):
    im, d = canvas(30, 20)
    flap = [-7, -2, 4, -1][i % 4] if kind != "attack" else [-6, -8, 2, 5][i % 4]
    dive = 0 if kind != "attack" else [0, -1, 2, 3][i % 4]
    cx, cy = 15, 10 + dive
    body, hi, wing = (70, 44, 92, 255), (120, 84, 150, 255), (52, 30, 70, 255)
    for s in (-1, 1):
        sh = (cx + s * 2, cy - 1)
        tip = (cx + s * 13, cy + flap)
        mid = (cx + s * 8, cy + flap // 2 - 3)
        d.polygon([sh, mid, tip, (cx + s * 9, cy + 3 + flap // 3), (cx + s * 4, cy + 4)], fill=wing)
        line(d, sh, mid, hi)
        line(d, mid, tip, hi)
    ell(d, cx, cy, 3, 4, body)
    d.polygon([(cx - 3, cy - 3), (cx - 2, cy - 7), (cx - 1, cy - 3)], fill=body)
    d.polygon([(cx + 1, cy - 3), (cx + 2, cy - 7), (cx + 3, cy - 3)], fill=body)
    rect(d, cx - 1, cy - 3, 2, 2, hi)
    d.point([(cx - 2, cy - 1), (cx + 1, cy - 1)], fill=(255, 60, 60, 255))
    if kind == "attack":
        d.point([(cx - 1, cy + 2), (cx + 1, cy + 2)], fill=(240, 240, 230, 255))
    return outline(im)


# ---------------------------------------------------------------- ghoul
def ghoul(kind, i, n):
    im, d = canvas(28, 26)
    skin, skin_hi = (112, 140, 98, 255), (150, 176, 120, 255)
    shirt, shirt_d = (106, 74, 50, 255), (76, 50, 34, 255)
    pants = (60, 62, 78, 255)
    helm, lamp = (212, 170, 60, 255), (255, 246, 170, 255)
    ph = i / n * math.tau
    step = math.sin(ph) * 3 if kind == "walk" else 0
    bob = -abs(round(math.cos(ph))) if kind == "walk" else 0
    hip = (13, 18 + bob)
    # legs
    for s, col in ((1, (44, 46, 60, 255)), (-1, pants)):
        fx = hip[0] + s * step
        line(d, hip, (fx, 24), col, 2)
        rect(d, fx - 1, 24, 3, 2, (40, 30, 24, 255))
    # hunched torso
    ell(d, 13, 14 + bob, 5, 5, shirt)
    rect(d, 9, 13 + bob, 9, 3, shirt_d)
    # head forward
    hx, hy = 17, 8 + bob
    ell(d, hx, hy, 4, 4, skin)
    rect(d, hx - 1, hy - 2, 3, 1, skin_hi)
    d.point([(hx + 2, hy), (hx + 1, hy)], fill=(255, 230, 80, 255))
    rect(d, hx - 4, hy - 5, 8, 3, helm)
    rect(d, hx + 3, hy - 4, 2, 2, lamp)
    rect(d, hx + 1, hy + 2, 3, 1, (60, 30, 30, 255))
    # arms + pick
    sh = (15, 12 + bob)
    if kind == "attack":
        ang = [-2.6, -2.9, -0.6, 0.3][i % 4]
    else:
        ang = 0.5 + math.sin(ph + math.pi) * 0.35
    hand = (sh[0] + math.sin(ang) * -1 * -6, sh[1] + math.cos(ang) * 6)
    hand = (sh[0] + 6 * math.cos(ang - math.pi / 2 + math.pi), sh[1] + 6 * math.sin(ang + math.pi / 2))
    hand = (sh[0] + 6 * math.sin(-ang + math.pi), sh[1] + 6 * math.cos(-ang + math.pi) * -1)
    line(d, sh, hand, skin, 2)
    tip = (hand[0] + 6 * math.sin(-ang + math.pi), hand[1] - 6 * math.cos(-ang + math.pi))
    line(d, hand, tip, (120, 84, 50, 255))
    hd = (tip[0] - 3 * math.cos(ang), tip[1] - 3 * math.sin(ang))
    he = (tip[0] + 3 * math.cos(ang), tip[1] + 3 * math.sin(ang))
    line(d, hd, he, (170, 176, 188, 255))
    return outline(im)


# ---------------------------------------------------------------- golem
def golem(kind, i, n):
    im, d = canvas(38, 32)
    rock, rock_hi, rock_d = (122, 100, 82, 255), (164, 140, 112, 255), (82, 66, 54, 255)
    amber, amber_hi = (236, 150, 40, 255), (255, 220, 120, 255)
    ph = i / n * math.tau
    bob = round(math.sin(ph * 2)) if kind == "walk" else 0
    step = math.sin(ph) * 3 if kind == "walk" else 0
    # legs
    for s in (-1, 1):
        lx = 19 + s * 5 + (step * s if kind == "walk" else 0)
        rect(d, lx - 3, 24, 6, 7, rock_d)
        rect(d, lx - 3, 24, 6, 2, rock)
    # body
    by = 16 + bob
    ell(d, 19, by, 10, 9, rock)
    ell(d, 17, by - 3, 6, 4, rock_hi)
    for (cx, cy) in ((13, by - 6), (24, by - 7), (20, by - 9)):
        d.polygon([(cx - 2, cy + 2), (cx, cy - 3), (cx + 2, cy + 2)], fill=amber)
        d.point([(cx, cy - 1)], fill=amber_hi)
    # head
    rect(d, 22, by - 5, 6, 5, rock_d)
    d.point([(26, by - 3), (24, by - 3)], fill=(255, 190, 60, 255))
    # arms
    if kind == "attack":
        lift = [-10, -14, 2, 6][i % 4]
    else:
        lift = round(math.sin(ph + math.pi) * 2)
    for s, col in ((-1, rock_d), (1, rock)):
        ax = 19 + s * 11
        ay = by + 2 + lift * (1 if s > 0 else 0.6)
        ell(d, ax, ay, 4, 5, col)
        rect(d, ax - 3, ay + 3, 6, 3, rock_d)
    if kind == "attack" and i % 4 >= 2:
        for k in range(3):
            d.point([(30 + k * 2, 30 - k)], fill=(200, 190, 170, 255))
    return outline(im)


# --------------------------------------------------------------- spider
def spider(kind, i, n):
    im, d = canvas(34, 20)
    body, hi, leg = (58, 40, 52, 255), (102, 70, 88, 255), (40, 28, 38, 255)
    ph = i / n * math.tau
    rear = 0 if kind != "attack" else [1, 3, 4, 1][i % 4]
    cy = 11 - rear // 2
    # legs: 4 per side
    for k in range(4):
        off = math.sin(ph + k * 1.7) * 2 if kind == "walk" else 0
        for s in (-1, 1):
            kx = 16 + s * (2 + k)
            knee = (kx + s * 5, cy - 5 + (k % 2))
            foot = (kx + s * (8 + k) + off * s, 19)
            if kind == "attack" and k == 0 and s == 1:
                knee = (kx + 6, cy - 6 - rear)
                foot = (kx + 9, cy - 8 - rear)
            line(d, (kx, cy), knee, leg)
            line(d, knee, foot, leg)
    ell(d, 11, cy, 7, 5, body)
    ell(d, 9, cy - 2, 3, 2, hi)
    rect(d, 7, cy - 1, 5, 1, (190, 40, 60, 255))
    ell(d, 20, cy + 1, 4, 3, body)
    for e in ((22, cy), (23, cy - 1), (21, cy - 1)):
        d.point([e], fill=(255, 80, 80, 255))
    if kind == "attack":
        d.point([(24, cy + 3), (23, cy + 4)], fill=(240, 240, 220, 255))
    return outline(im)


# ---------------------------------------------------------------- mimic
def mimic(kind, i, n):
    im, d = canvas(26, 26)
    stone, stone_hi, stone_d = (100, 104, 120, 255), (140, 146, 162, 255), (66, 68, 84, 255)
    gold, gold_hi = (226, 182, 60, 255), (255, 236, 140, 255)
    hop = 0
    legs = 0
    if kind == "walk":
        hop = [0, -2, -3, -1][i % 4]
        legs = 1
    open_ = 0 if kind != "attack" else [3, 7, 4][i % 3]
    base_y = 24 + hop
    # legs
    if legs:
        for s in (-1, 1):
            line(d, (13 + s * 4, base_y - 2), (13 + s * 6, base_y + 1 - hop), (60, 40, 40, 255))
    # lower jaw block
    rect(d, 3, base_y - 10, 20, 10, stone)
    rect(d, 3, base_y - 3, 20, 3, stone_d)
    # mouth inside
    if open_:
        rect(d, 4, base_y - 10 - open_, 18, open_, (90, 20, 30, 255))
        for tx in range(5, 21, 3):
            d.polygon([(tx, base_y - 10), (tx + 1, base_y - 12), (tx + 2, base_y - 10)], fill=(240, 236, 220, 255))
            d.polygon([(tx, base_y - 10 - open_), (tx + 1, base_y - 8 - open_), (tx + 2, base_y - 10 - open_)], fill=(240, 236, 220, 255))
        line(d, (10, base_y - 10), (16, base_y - 11 - open_ // 2), (230, 90, 110, 255))
    # lid
    ly = base_y - 20 - open_
    rect(d, 3, ly, 20, 10, stone)
    rect(d, 3, ly, 20, 2, stone_hi)
    for (gx, gy) in ((7, ly + 4), (15, ly + 3), (11, ly + 7), (18, ly + 6), (8, base_y - 6), (17, base_y - 7)):
        rect(d, gx, gy, 2, 2, gold)
        d.point([(gx, gy)], fill=gold_hi)
    if kind != "idle":
        d.point([(9, ly + 8), (17, ly + 8)], fill=(255, 70, 70, 255))
    return outline(im)


# ----------------------------------------------------------------- worm
def worm(kind, i, n):
    im, d = canvas(36, 18)
    flesh, hi, dark = (196, 120, 110, 255), (232, 168, 150, 255), (140, 76, 72, 255)
    ph = i / max(1, n) * math.tau
    segs = 7
    pts = []
    for k in range(segs):
        x = 5 + k * 4
        rear = 0
        if kind == "attack" and k >= segs - 3:
            rear = [2, 5, 7, 3][i % 4] * (k - (segs - 4)) / 3
        y = 13 - math.sin(ph + k * 0.9) * (1.5 if kind != "attack" else 0.6) - rear
        pts.append((x, y))
    for k, (x, y) in enumerate(pts):
        r = 3 if k < segs - 1 else 4
        ell(d, x, y, r, r, flesh if k % 2 == 0 else dark)
        d.point([(round(x - 1), round(y - r + 1))], fill=hi)
    hx, hy = pts[-1]
    mouth = 1 if kind != "attack" else [1, 2, 3, 2][i % 4]
    rect(d, hx + 2, hy - mouth, 2, mouth * 2, (70, 20, 30, 255))
    d.point([(round(hx + 3), round(hy - mouth)), (round(hx + 3), round(hy + mouth - 1))], fill=(240, 230, 210, 255))
    return outline(im)


ENEMIES = {
    "cave-bat-swarm": (bat, 4, 4),
    "miner-ghoul": (ghoul, 4, 4),
    "rock-golem": (golem, 4, 4),
    "cave-spider": (spider, 4, 4),
    "ore-mimic": (mimic, 4, 3),
    "tunnel-worm": (worm, 2, 4),
}


# ------------------------------------------------------------ deaths
# Phase 13: every enemy gets its own 6-frame death, derived from its own
# pixels: white hit-flash, then a per-species motion, then a dissolve.
# Death canvases get 10 px of headroom (lids / bodies fly up); the feet
# row stays the canvas bottom so the corpse lines up with the enemy.
import random as _r
PAD = 10


def _pad(im):
    c = Image.new("RGBA", (im.width + 8, im.height + PAD), (0, 0, 0, 0))
    c.alpha_composite(im, (4, PAD))
    return c


def _flash(im):
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (255, 255, 255, 255) if (r, g, b) != OUTLINE[:3] else OUTLINE
    return out


def _dissolve(im, frac, seed):
    out = im.copy()
    px = out.load()
    rng = _r.Random(seed)
    for y in range(out.height):
        for x in range(out.width):
            if px[x, y][3] and rng.random() < frac:
                px[x, y] = (0, 0, 0, 0)
    return out


def _bottom(im, w, h):
    c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    c.alpha_composite(im, ((w - im.width) // 2, h - im.height))
    return c


def _squash(im, sx, sy):
    return im.resize((max(1, round(im.width * sx)), max(1, round(im.height * sy))), Image.NEAREST)


def _crop_alpha(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def death_frames(slug, idle):
    base = _pad(idle)
    W, H = base.size
    body = _crop_alpha(idle)
    frames = [_bottom(_flash(body), W, H)]
    rng = _r.Random(hash(slug) & 0xFFFF)
    if slug == "cave-bat-swarm":
        # wings fold, the bat flips belly-up and drops
        for k, (sx, rot) in enumerate([(0.7, 0), (0.5, 90), (0.45, 180), (0.45, 180)]):
            f = _squash(body, sx, 1.0).rotate(rot, expand=True)
            frames.append(_bottom(f if k < 3 else _dissolve(f, 0.4, 3), W, H))
    elif slug == "miner-ghoul":
        # knees buckle, slumps forward, collapses into a heap
        for k, (sy, rot) in enumerate([(0.9, -15), (0.85, -45), (0.8, -80), (0.75, -90)]):
            f = _crop_alpha(_squash(body, 1.0, sy).rotate(rot, expand=True))
            frames.append(_bottom(f if k < 3 else _dissolve(f, 0.35, 5), W, H))
    elif slug == "rock-golem":
        # crumbles: 4x4 chunks tumble down into a rubble pile
        chunks = []
        for y in range(0, body.height, 4):
            for x in range(0, body.width, 4):
                c = body.crop((x, y, x + 4, y + 4))
                if c.getbbox():
                    chunks.append((x, y, c, rng.uniform(0.6, 1.4), rng.randint(-3, 3)))
        ox = (W - body.width) // 2
        oy = H - body.height
        for k in range(1, 5):
            f = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            for (x, y, c, sp, dx) in chunks:
                ny = min(H - 4 - rng.randint(0, 1) * 2, oy + y + round(k * k * 2.2 * sp))
                f.alpha_composite(c, (max(0, min(W - 4, ox + x + dx * k // 2)), ny))
            frames.append(f)
    elif slug == "cave-spider":
        # flips onto its back, legs curl in
        for k, sx in enumerate([0.95, 0.8, 0.7, 0.65]):
            f = _squash(body, sx, 1.0)
            if k >= 1:
                f = f.transpose(Image.FLIP_TOP_BOTTOM)
            frames.append(_bottom(f if k < 3 else _dissolve(f, 0.35, 7), W, H))
    elif slug == "ore-mimic":
        # lid bursts open and flies up, the jaw block breaks apart
        half = body.height // 2
        lid = body.crop((0, 0, body.width, half))
        jaw = body.crop((0, half, body.width, body.height))
        for k in range(1, 5):
            f = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            lx = (W - body.width) // 2
            f.alpha_composite(jaw if k < 3 else _dissolve(jaw, 0.3 * (k - 2), 11), (lx, H - jaw.height))
            ly = H - body.height - [3, 7, 9, 8][k - 1]
            lidr = lid.rotate([10, 25, 45, 60][k - 1], expand=True)
            f.alpha_composite(lidr if k < 4 else _dissolve(lidr, 0.4, 13), (min(W - lidr.width, lx + k * 2), max(0, ly)))
            frames.append(f)
    else:  # tunnel-worm
        # thrashes, then burrows down into the floor
        for k in range(1, 5):
            f = _squash(body, 1.0, [0.8, 1.1, 0.6, 0.35][k - 1])
            frames.append(_bottom(f, W, H))
    frames.append(_dissolve(frames[-1], 0.7, 17))
    return frames


LOOT = {
    "stone": ([".oooo.", "oaabao", "oabbao", "oaaaco", "ocacco", ".oooo."], {"o": (30, 30, 38), "a": (130, 134, 146), "b": (176, 180, 192), "c": (90, 92, 104)}),
    "coal": ([".oooo.", "oabaao", "oaaaco", "oacaao", "occaco", ".oooo."], {"o": (12, 12, 14), "a": (50, 50, 56), "b": (110, 110, 120), "c": (30, 30, 34)}),
    "gold": ([".oooo.", "obbaao", "obaaco", "oaaaco", "oacaco", ".oooo."], {"o": (60, 40, 10), "a": (230, 180, 50), "b": (255, 240, 150), "c": (170, 120, 30)}),
    "amber": ([".oooo.", "obaaao", "oaaaco", "oaacao", "oacaco", ".oooo."], {"o": (70, 30, 6), "a": (240, 150, 40), "b": (255, 220, 140), "c": (190, 100, 20)}),
    "wood": (["oooooo", "obbbbo", "oaaaao", "oacaao", "oaaaco", "oooooo"], {"o": (40, 24, 12), "a": (150, 98, 52), "b": (200, 146, 86), "c": (104, 64, 32)}),
}


def main():
    for name, (rows, pal) in LOOT.items():
        os.makedirs(os.path.join(OUT, "..", "hero", "loot"), exist_ok=True)
        im = Image.new("RGBA", (6, 6), (0, 0, 0, 0))
        for y, r in enumerate(rows):
            for x, ch in enumerate(r):
                if ch in pal:
                    im.putpixel((x, y), pal[ch] + (255,))
        im.save(os.path.join(OUT, "..", "hero", "loot", name + ".png"))
    for slug, (fn, nw, na) in ENEMIES.items():
        folder = os.path.join(OUT, slug)
        os.makedirs(folder, exist_ok=True)
        fn("idle", 0, 1).save(os.path.join(folder, "idle.png"))
        for i in range(nw):
            fn("walk", i, nw).save(os.path.join(folder, "walk_%d.png" % i))
        for i in range(na):
            fn("attack", i, na).save(os.path.join(folder, "attack_%d.png" % i))
        for i, f in enumerate(death_frames(slug, fn("idle", 0, 1))):
            f.save(os.path.join(folder, "death_%d.png" % i))
    print("enemy frames written to", OUT)


if __name__ == "__main__":
    main()
