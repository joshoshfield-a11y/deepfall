"""build_pixel_tiles.py - DEEPFALL Phase 14 pixel-art tileset.

Replaces the painted tiles with a crisp 16x16 pixel tileset (x4 =
64 px, nearest) that matches the pixel hero / enemies: chunky cobbles
with top-left highlights, pebbled dirt, grass lips, sparkling ore gems,
planks, bricks, moss, sand, obsidian, dark background walls, rock<->dirt
transition tiles, rounded outer corners, edge rims and a crack overlay.
Every variant is seeded, so the world stays deterministic.

Output: assets/tiles_px/<name>_v<k>.png, edge_*.png, corner_*.png,
damage.png, vein_glow_<k>.png (Phase 14 ore-vein overlay frames).
Run:  python3 build_pixel_tiles.py
"""
import os
import random
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "assets", "tiles_px")
S = 16
SCALE = 4

PALS = {
    "stone": [(46, 48, 60), (74, 78, 94), (98, 104, 122), (128, 136, 156)],
    "dirt": [(58, 36, 24), (92, 60, 38), (120, 82, 52), (150, 108, 70)],
    "sand": [(150, 120, 70), (190, 158, 98), (216, 186, 124), (236, 212, 156)],
    "obsidian": [(16, 10, 26), (34, 22, 52), (58, 40, 88), (110, 86, 170)],
    "wall_stone": [(18, 20, 28), (28, 30, 40), (36, 40, 52), (46, 50, 64)],
    "wall_dirt": [(24, 16, 12), (36, 24, 18), (46, 32, 24), (58, 42, 30)],
    "wood": [(56, 32, 16), (104, 66, 34), (140, 94, 50), (176, 126, 72)],
    "brick": [(52, 26, 22), (120, 56, 44), (150, 76, 58), (180, 104, 80)],
}


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def put(im, x, y, c, a=255):
    if 0 <= x < S and 0 <= y < S:
        im.putpixel((x, y), tuple(c[:3]) + (a,))


def get(im, x, y):
    return im.getpixel((x % S, y % S))


def cobble(rng, pal, density=7):
    """Stone: mid fill, scattered cobbles (light top-left, dark rim)."""
    im = new()
    for y in range(S):
        for x in range(S):
            put(im, x, y, pal[1] if rng.random() > 0.12 else pal[0])
    for _ in range(density):
        cx, cy = rng.randrange(S), rng.randrange(S)
        w, h = rng.randint(3, 5), rng.randint(2, 4)
        for dy in range(h):
            for dx in range(w):
                if (dx in (0, w - 1)) and (dy in (0, h - 1)):
                    continue
                x, y = (cx + dx) % S, (cy + dy) % S
                c = pal[2]
                if dy == 0 or dx == 0:
                    c = pal[3]
                if dy == h - 1 or dx == w - 1:
                    c = pal[1]
                put(im, x, y, c)
        for dx in range(1, w):
            put(im, (cx + dx) % S, (cy + h) % S, pal[0])
        for dy in range(1, h):
            put(im, (cx + w) % S, (cy + dy) % S, pal[0])
    return im


def pebbly(rng, pal, pebbles=6, roots=False):
    im = new()
    for y in range(S):
        for x in range(S):
            r = rng.random()
            put(im, x, y, pal[1] if r > 0.18 else (pal[2] if r > 0.08 else pal[0]))
    for _ in range(pebbles):
        x, y = rng.randrange(S), rng.randrange(S)
        put(im, x, y, pal[3]); put(im, x + 1, y, pal[2]); put(im, x, y + 1, pal[0]); put(im, x + 1, y + 1, pal[0])
    if roots:
        x = rng.randrange(S)
        for y in range(rng.randint(3, 8)):
            put(im, x, y, (70, 46, 30))
            x += rng.choice((-1, 0, 0, 1))
    return im


def gems(base, rng, cols, n=3, size=(2, 3)):
    im = base.copy()
    for _ in range(n):
        cx, cy = rng.randint(2, S - 4), rng.randint(2, S - 4)
        sz = rng.randint(*size)
        for dy in range(sz):
            for dx in range(sz):
                if dx + dy > sz:
                    continue
                put(im, cx + dx, cy + dy, cols[1])
        put(im, cx, cy, cols[2])
        put(im, cx + sz - 1, cy + sz - 1, cols[0])
        put(im, cx + sz, cy + 1, cols[0])
    return im


def grass(rng):
    im = pebbly(rng, PALS["dirt"], 4)
    g = [(30, 80, 30), (52, 128, 44), (92, 170, 62), (150, 210, 90)]
    for x in range(S):
        h = rng.randint(3, 5)
        for y in range(h):
            put(im, x, y, g[2] if y == 0 else g[1])
        put(im, x, h, g[0])
        if rng.random() < 0.3:
            put(im, x, h + 1, g[0])
        if rng.random() < 0.35:
            put(im, x, 0, g[3])
    return im


def planks(rng, pal):
    im = new()
    for y in range(S):
        row = y // 4
        for x in range(S):
            c = pal[2]
            if y % 4 == 0:
                c = pal[3]
            if y % 4 == 3:
                c = pal[0]
            if rng.random() < 0.08 and y % 4 in (1, 2):
                c = pal[1]
            put(im, x, y, c)
        if y % 4 == 1:
            sx = (row * 5 + rng.randint(0, 3)) % S
            put(im, sx, y, pal[0]); put(im, sx, y + 1, pal[0])
    for (x, y) in ((2, 1), (13, 5), (3, 9), (12, 13)):
        put(im, x, y, (160, 160, 170))
    return im


def platform(rng):
    pal = PALS["wood"]
    im = new()
    for y in range(5):
        for x in range(S):
            put(im, x, y, pal[3] if y == 0 else (pal[0] if y == 4 else pal[2]))
        if y == 2:
            put(im, rng.randint(2, 6), y, pal[1]); put(im, rng.randint(9, 13), y, pal[1])
    for bx in (2, 12):
        for y in range(5, 9):
            put(im, bx + (y - 5) // 2, y, pal[1])
            put(im, bx + (y - 5) // 2 + 1, y, pal[0])
    return im


def bricks(rng):
    pal = PALS["brick"]
    im = new()
    for y in range(S):
        off = 4 if (y // 4) % 2 else 0
        for x in range(S):
            if y % 4 == 3 or (x + off) % 8 == 7:
                c = (40, 30, 30)
            elif y % 4 == 0 or (x + off) % 8 == 0:
                c = pal[3]
            else:
                c = pal[2] if rng.random() > 0.15 else pal[1]
            put(im, x, y, c)
    return im


def moss(base, rng):
    im = base.copy()
    g = [(30, 70, 34), (54, 110, 50), (90, 150, 70)]
    for x in range(S):
        h = rng.randint(1, 4)
        for y in range(h):
            put(im, x, y, g[1] if y else g[2])
    for _ in range(4):
        x, y = rng.randrange(S), rng.randint(4, S - 1)
        put(im, x, y, g[0]); put(im, x + 1, y, g[1])
    return im


def cracks(base, rng, col=(20, 20, 26)):
    im = base.copy()
    for _ in range(2):
        x, y = rng.randrange(S), 0
        while y < S:
            put(im, x, y, col)
            put(im, x + 1, y, (base.getpixel((min(S - 1, x + 1), y))[0] + 20,) * 3)
            y += 1
            x += rng.choice((-1, 0, 1))
    return im


def sand_tile(rng):
    pal = PALS["sand"]
    im = new()
    for y in range(S):
        for x in range(S):
            r = rng.random()
            c = pal[2] if (x + y) % 2 else pal[1]
            if r < 0.07:
                c = pal[3]
            elif r < 0.12:
                c = pal[0]
            put(im, x, y, c)
    for y in (4, 10):
        for x in range(S):
            if (x + y) % 5 == 0:
                put(im, x, y, pal[0])
    return im


def obsidian_tile(rng):
    pal = PALS["obsidian"]
    im = cobble(rng, pal, 5)
    for _ in range(3):
        x, y = rng.randrange(S), rng.randrange(S)
        for k in range(3):
            put(im, x + k, y - k, pal[3])
    return im


def blend_side(a, b, side, depth=5, rng=None):
    """a tile with b's material bleeding in from `side` (N/E/S/W)."""
    im = a.copy()
    for y in range(S):
        for x in range(S):
            d = {"N": y, "S": S - 1 - y, "W": x, "E": S - 1 - x}[side]
            edge = depth + (rng.randint(-1, 1) if rng else 0)
            if d < edge:
                im.putpixel((x, y), b.getpixel((x, y)))
            elif d == edge:
                im.putpixel((x, y), (30, 22, 18, 255))
    return im


def round_corner(a, corner, rim=(14, 12, 18)):
    im = a.copy()
    r = 6
    cx = r if corner[1] == "L" else S - 1 - r
    cy = r if corner[0] == "T" else S - 1 - r
    for y in range(S):
        for x in range(S):
            inx = (x < cx) if corner[1] == "L" else (x > cx)
            iny = (y < cy) if corner[0] == "T" else (y > cy)
            if inx and iny:
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d > r + 0.5:
                    im.putpixel((x, y), (0, 0, 0, 0))
                elif d > r - 0.7:
                    im.putpixel((x, y), rim + (255,))
    return im


def edge(side):
    im = new()
    for i in range(S):
        for k, a in ((0, 255), (1, 120), (2, 50)):
            hl = side == "top" and k == 1
            col = (190, 196, 210) if hl else (10, 10, 14)
            alpha = 90 if hl else a
            pos = {"top": (i, k), "bottom": (i, S - 1 - k), "left": (k, i), "right": (S - 1 - k, i)}[side]
            put(im, pos[0], pos[1], col, alpha)
    return im


def corner_overlay(c):
    im = new()
    x0 = 0 if c[1] == "l" else S - 2
    y0 = 0 if c[0] == "t" else S - 2
    for dy in range(2):
        for dx in range(2):
            put(im, x0 + dx, y0 + dy, (10, 10, 14), 200)
    return im


def damage():
    rng = random.Random(99)
    im = new()
    for start in ((5, 2), (10, 8), (3, 11)):
        x, y = start
        for _ in range(6):
            put(im, x, y, (12, 10, 14), 230)
            put(im, x + 1, y, (200, 200, 210), 90)
            x += rng.choice((-1, 1))
            y += rng.choice((0, 1, 1))
    return im


def vein_glow(k):
    """Glowing vein overlay: bright gold/white crystal seams that pulse
    (4 frames, drawn additively in-game)."""
    rng = random.Random(500)
    im = new()
    seams = []
    for _ in range(3):
        x, y = rng.randrange(S), rng.randrange(S)
        pts = []
        for _ in range(7):
            pts.append((x, y))
            x = (x + rng.choice((1, 1, 0))) % S
            y = (y + rng.choice((-1, 0, 1))) % S
        seams.append(pts)
    for si, pts in enumerate(seams):
        for i, (x, y) in enumerate(pts):
            ph = (i + k * 2 + si) % 7
            a = 255 if ph < 2 else (150 if ph < 4 else 70)
            put(im, x, y, (255, 230, 120), a)
            if ph == 0:
                put(im, x, y, (255, 255, 235), 255)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    put(im, x + dx, y + dy, (255, 200, 80), 140)
    return im


def save(im, name):
    os.makedirs(OUT, exist_ok=True)
    im.resize((S * SCALE, S * SCALE), Image.NEAREST).save(os.path.join(OUT, name + ".png"))


GOLD = [(150, 100, 20), (240, 190, 50), (255, 246, 170)]
AMBER = [(160, 70, 10), (240, 140, 30), (255, 220, 140)]
COAL = [(10, 10, 12), (28, 28, 32), (80, 80, 92)]


def main():
    builders = {
        "stone": lambda r: cobble(r, PALS["stone"]),
        "dirt": lambda r: pebbly(r, PALS["dirt"], 6, r.random() < 0.3),
        "grass-dirt": grass,
        "gold-ore": lambda r: gems(cobble(r, PALS["stone"]), r, GOLD, 4),
        "amber-ore": lambda r: gems(cobble(r, PALS["stone"]), r, AMBER, 3, (2, 4)),
        "coal-ore": lambda r: gems(cobble(r, PALS["stone"]), r, COAL, 5),
        "wood": lambda r: planks(r, PALS["wood"]),
        "wood-platform": platform,
        "brick": bricks,
        "mossy-stone": lambda r: moss(cobble(r, PALS["stone"]), r),
        "cracked-stone": lambda r: cracks(cobble(r, PALS["stone"]), r),
        "sand": sand_tile,
        "obsidian": obsidian_tile,
        "dirt-wall": lambda r: pebbly(r, PALS["wall_dirt"], 4),
        "cave-wall-dark": lambda r: cobble(r, PALS["wall_stone"], 6),
    }
    counts = {"stone": 16, "dirt": 16}
    for name, fn in builders.items():
        for v in range(counts.get(name, 4)):
            save(fn(random.Random(hash((name, v)) & 0xFFFFFF)), "%s_v%d" % (name, v))
    for side in "NESW":
        r = random.Random(ord(side))
        save(blend_side(cobble(r, PALS["stone"]), pebbly(r, PALS["dirt"]), side, 5, r), "trans_rock_%s_v0" % side)
        save(blend_side(pebbly(r, PALS["dirt"]), cobble(r, PALS["stone"]), side, 5, r), "trans_dirt_%s_v0" % side)
    for c in ("TL", "TR", "BL", "BR"):
        r = random.Random(c.__hash__() & 0xFFFF)
        save(round_corner(cobble(r, PALS["stone"]), c), "corner_rock_%s_v0" % c)
        save(round_corner(pebbly(r, PALS["dirt"]), c), "corner_dirt_%s_v0" % c)
    for side in ("top", "bottom", "left", "right"):
        save(edge(side), "edge_" + side)
    for c in ("tl", "tr", "bl", "br"):
        save(corner_overlay(c), "corner_" + c)
    save(damage(), "damage")
    for k in range(4):
        save(vein_glow(k), "vein_glow_%d" % k)
    print("tiles written to", OUT)


if __name__ == "__main__":
    main()
