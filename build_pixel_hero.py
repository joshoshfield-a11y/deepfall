"""build_pixel_hero.py - DEEPFALL Phase 11 pixel-art paper-doll parts.

Terraria-style modular hero: every class is drawn from the same part
templates (head / torso / arm / leg) with its own palette, plus held
tools and breakable / pushable props. Parts are tiny (art pixels) and
scaled x3 in-game with nearest filtering, so they read as crisp pixel
art and animate procedurally (hero_rig.gd) instead of fixed frames.

Run:  python3 build_pixel_hero.py   (writes assets/hero/...)
"""
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "assets", "hero")

# ---------------------------------------------------------------- palettes
PAL = {
    "tech": {
        "o": (18, 20, 28), "a": (92, 104, 122), "b": (150, 164, 182),
        "c": (56, 64, 80), "v": (90, 230, 255), "w": (210, 250, 255),
        "s": (226, 170, 128), "h": (40, 44, 58), "t": (60, 200, 230),
        "k": (36, 40, 52), "m": (120, 90, 60), "g": (200, 170, 70),
    },
    "red": {
        "o": (24, 12, 14), "a": (160, 40, 44), "b": (214, 84, 76),
        "c": (98, 22, 30), "v": (255, 200, 90), "w": (255, 240, 190),
        "s": (210, 150, 110), "h": (60, 30, 30), "t": (240, 190, 70),
        "k": (52, 34, 34), "m": (110, 80, 50), "g": (230, 190, 80),
    },
    "mage": {
        "o": (14, 12, 26), "a": (66, 52, 120), "b": (108, 92, 176),
        "c": (38, 28, 74), "v": (130, 255, 220), "w": (220, 255, 245),
        "s": (200, 160, 130), "h": (24, 18, 44), "t": (120, 240, 210),
        "k": (34, 26, 58), "m": (100, 70, 44), "g": (220, 200, 110),
    },
}

HEADS = {
    "tech": [
        "...oooooo..",
        "..obbbbaao.",
        ".obbaaaaaco",
        ".oaaaaaaaco",
        ".oaaoovvvvo",
        ".oaaowwvvvo",
        ".oaaaoooooo",
        ".ocaaaaaco.",
        "..occcccoo.",
        "...ooooo...",
    ],
    "red": [
        "..ttt......",
        ".ttoooooo..",
        ".toabbbbao.",
        "..oaaaaaaao",
        ".oaaaaaaaao",
        ".oaacooooco",
        ".oaacvvvvvo",
        ".oaaaoooooo",
        "..occaaaco.",
        "...ooooooo.",
    ],
    "mage": [
        ".....oo....",
        "....obao...",
        "...obaaao..",
        "..obaaaaao.",
        ".obaahhhhao",
        ".oaahhhvhvo",
        ".oaahhhhhho",
        ".oaaahhhhao",
        "..ocaaaaco.",
        "...oooooo..",
    ],
}

TORSO = [
    "..oooooo..",
    ".oabbbbao.",
    "oabbaaaaco",
    "oabaaaaaco",
    "oaaattaaco",
    "oaaaaaaaco",
    "oaaaaaaaco",
    "ookkgkkkoo",
    ".occcccco.",
    "..oooooo..",
]
MAGE_TORSO = [
    "..oooooo..",
    ".oabbbbao.",
    "oabbaaaaco",
    "oabaattaco",
    "oaaaattaco",
    "oaaaaaaaco",
    "okkkgkkkko",
    "oaaaaaaaco",
    "oabaaaaaco",
    "oooooooooo",
]
ARM = [
    ".oo.",
    "obao",
    "obao",
    "oaco",
    "oaco",
    "okko",
    "oaco",
    "osso",
    ".oo.",
]
LEG = [
    "oooo.",
    "oaco.",
    "oaco.",
    "oaco.",
    "okko.",
    "oaco.",
    "okkoo",
    "okkkko",
    "oooooo",
]

TOOLS = {
    # grip at the bottom-centre pixel; pointing "up" (rig rotates them)
    "pickaxe": ([
        "..ooooooooo..",
        ".obbbbbbbbbo.",
        "ob ooomooo bo",
        "oo...omo...oo",
        ".....omo.....",
        ".....omo.....",
        ".....omo.....",
        ".....omo.....",
        ".....omo.....",
        ".....omo.....",
        ".....okmo....",
        ".....okko....",
        "......oo.....",
    ], {"o": (20, 18, 22), "b": (190, 196, 206), "m": (132, 92, 54), "k": (82, 56, 34), " ": (120, 126, 140)}),
    "sword": ([
        "....o....",
        "...owo...",
        "...owbo..",
        "...owbo..",
        "...owbo..",
        "...owbo..",
        "...owbo..",
        "...owbo..",
        "...owbo..",
        "...owbo..",
        ".oooooooo",
        ".oggggggo",
        "..oommo..",
        "...omo...",
        "...omo...",
        "...ogo...",
        "....o....",
    ], {"o": (18, 20, 28), "w": (236, 244, 255), "b": (150, 170, 196), "g": (220, 180, 70), "m": (110, 60, 40)}),
    "staff": ([
        ".ooo.",
        "ovwvo",
        "owwwo",
        "ovwvo",
        ".omo.",
        ".omo.",
        ".omo.",
        ".omo.",
        ".omo.",
        ".omo.",
        ".omo.",
        ".omo.",
        ".omo.",
        ".omo.",
        ".ogo.",
        "..o..",
    ], {"o": (16, 14, 26), "v": (90, 230, 200), "w": (210, 255, 245), "m": (110, 76, 46), "g": (210, 190, 90)}),
}

PROPS = {
    "workbench": ([
        "oooooooooooooooo",
        "obbbbbbbbbbbbbbo",
        "oaaaaaaaaaaaaaco",
        "occcccccccccccco",
        ".oao.mmm....oao.",
        ".oao.mwm....oao.",
        ".oao.ooo....oao.",
        ".oaooooooooooao.",
        ".oaaaaaaaaaaaao.",
        ".oaoccccccccoao.",
        ".oao........oao.",
        ".oco........oco.",
        ".ooo........ooo.",
    ], {"o": (36, 22, 12), "a": (150, 98, 52), "b": (200, 146, 86), "c": (100, 62, 30), "m": (120, 124, 136), "w": (200, 206, 216)}),
    "crate": ([
        "oooooooooooooooo",
        "obbbbbbbbbbbbbbo",
        "obaaaaaaaaaaaaco",
        "obaooooooooooaco",
        "obao.cbbbbbc.aco",
        "obao.bc....c.aco",
        "obao.b.c...c.aco",
        "obao.b..c..c.aco",
        "obao.b...c.c.aco",
        "obao.b....cc.aco",
        "obao.bccccccoaco",
        "obaooooooooooaco",
        "obaaaaaaaaaaaaco",
        "occcccccccccccco",
        "oooooooooooooooo",
        "................",
    ], {"o": (40, 24, 14), "a": (150, 98, 52), "b": (196, 140, 80), "c": (104, 64, 32), ".": (124, 80, 42)}),
    "pot": ([
        "....oooooo....",
        "...obbbbbco...",
        "....oaaaco....",
        "...obaaaaco...",
        "..obaaaaaaco..",
        ".obaaggggaaco.",
        ".obaagaagaaco.",
        ".obaaggggaaco.",
        ".obaaaaaaaaco.",
        "..oaaaaaaacoo.",
        "...occccccco..",
        "....oooooo....",
    ], {"o": (34, 20, 18), "a": (168, 92, 60), "b": (214, 140, 96), "c": (110, 56, 40), "g": (230, 196, 90)}),
    "barrel": ([
        "..oooooooooo..",
        ".obbbbbbbbbbo.",
        "oaabbbbbbbbaao",
        "ommmmmmmmmmmmo",
        "oabbaaaaaaaaco",
        "oabaaaaaaaaaco",
        "oabaaaaaaaaaco",
        "ommmmmmmmmmmmo",
        "oabaaaaaaaaaco",
        "oabaaaaaaaaaco",
        "oabaaaaaaaaaco",
        "ommmmmmmmmmmmo",
        "oaacccccccccao",
        ".occcccccccco.",
        "..oooooooooo..",
        "..............",
    ], {"o": (30, 20, 14), "a": (140, 86, 46), "b": (184, 124, 70), "c": (94, 56, 28), "m": (98, 100, 110)}),
}


def render(rows, pal):
    w = max(len(r) for r in rows)
    im = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == "." and "." not in pal:
                continue
            col = pal.get(ch)
            if col is None:
                continue
            im.putpixel((x, y), col + (255,))
    return im


def save(im, *parts):
    p = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    im.save(p)


def preview(cls, head, torso, arm, leg, tool):
    # 3x scaled standing pose for the class-select card (40 x 64 px art)
    can = Image.new("RGBA", (40, 64), (0, 0, 0, 0))
    darker = lambda im: Image.eval(im, lambda v: int(v * 0.65))
    dl = darker(leg.convert("RGB")).convert("RGBA"); dl.putalpha(leg.split()[3])
    da = darker(arm.convert("RGB")).convert("RGBA"); da.putalpha(arm.split()[3])
    can.alpha_composite(da, (19, 28))
    can.alpha_composite(dl, (17, 45))
    can.alpha_composite(torso, (14, 37))
    can.alpha_composite(leg, (20, 45))
    can.alpha_composite(head, (13, 28))
    can.alpha_composite(tool, (19, 21))
    can.alpha_composite(arm, (16, 37))
    can = can.crop((4, 14, 36, 56))
    return can.resize((can.width * 4, can.height * 4), Image.NEAREST)


def main():
    for cls, pal in PAL.items():
        head = render(HEADS[cls], pal)
        torso = render(MAGE_TORSO if cls == "mage" else TORSO, pal)
        arm = render(ARM, pal)
        leg = render(LEG, pal)
        save(head, cls, "head.png")
        save(torso, cls, "torso.png")
        save(arm, cls, "arm.png")
        save(leg, cls, "leg.png")
        tname = "staff" if cls == "mage" else "sword"
        tool = render(*TOOLS[tname])
        save(preview(cls, head, torso, arm, leg, tool), cls, "preview.png")
    for name, (rows, pal) in TOOLS.items():
        save(render(rows, pal), "tools", name + ".png")
    for name, (rows, pal) in PROPS.items():
        save(render(rows, pal), "props", name + ".png")
    print("hero parts written to", OUT)


if __name__ == "__main__":
    main()
