#!/usr/bin/env python3
"""Build DEEPFALL Effekseer effects (procedural textures + .efkproj XML).

Effects:
  mage_orb_impact  - cyan/amber burst, frost-burst style (cyan 60,120,255 /
                      120,200,255 + amber 255,175,60), ~0.6 s, 24 shards.
  enemy_death_poof - grey smoke + orange embers, ~0.9 s.

The .efkproj XML mirrors the schema of Effekseer's own sample
`hit_eff.efkproj` (ToolVersion 1.43 / Version 3), which the 1.80.8 editor
loads fine. No GUI needed: export with the Effekseer CLI:

  Effekseer -cui -in mage_orb_impact.efkproj -e mage_orb_impact.efkefc

Textures are procedural (PIL), white so the particle ColorAll tints them.
NOTE: the exported .efkefc does NOT embed textures -- the Texture/
folder must travel with the .efkefc (same relative layout) and be copied
into res:// alongside it. Same for the Godot plugin.
"""
import math
import os
import random
import xml.etree.ElementTree as ET
from xml.dom import minidom

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------- textures
def soft_blob(size, power=2.0):
    """White radial-gradient blob, alpha falls off smoothly to 0 at edge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = size / 2.0
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - c + 0.5, y - c + 0.5) / c
            if r >= 1.0:
                continue
            a = max(0.0, 1.0 - r ** power)
            a = a * a * (3 - 2 * a)  # smoothstep
            px[x, y] = (255, 255, 255, int(255 * a))
    return img


def smoke_puff(size=128):
    """Irregular soft smoke blob: several overlapping blurred blobs."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rnd = random.Random(20261105)
    c = size / 2.0
    layer = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(layer)
    for _ in range(9):
        ox = rnd.uniform(-0.22, 0.22) * size
        oy = rnd.uniform(-0.22, 0.22) * size
        rad = rnd.uniform(0.18, 0.34) * size
        d.ellipse([c + ox - rad, c + oy - rad, c + ox + rad, c + oy + rad],
                  fill=rnd.randint(90, 150))
    layer = layer.filter(ImageFilter.GaussianBlur(size * 0.09))
    # radial mask so the puff fades at the canvas edge
    mask = Image.new("L", (size, size), 0)
    mp = mask.load()
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - c + 0.5, y - c + 0.5) / c
            mp[x, y] = int(255 * max(0.0, 1.0 - max(0.0, r - 0.55) / 0.45))
    from PIL import ImageChops
    alpha = ImageChops.multiply(layer, mask)
    white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    img.paste(white, (0, 0), alpha)
    return img


# ---------------------------------------------------------------- XML help
def el(parent, tag, text=None):
    e = ET.SubElement(parent, tag)
    if text is not None:
        e.text = str(text)
    return e


def rand3(parent, tag, center, lo, hi):
    """A <Tag><Center/><Max/><Min/></Tag> random-value block."""
    e = el(parent, tag)
    el(e, "Center", center)
    el(e, "Max", hi)
    el(e, "Min", lo)
    return e


def fixed(parent, tag, value):
    e = el(parent, tag)
    el(e, tag if False else "X", value)  # placeholder, replaced by caller
    return e


def common(node, life, maxgen=None, gentime=None, offset=None):
    cv = el(node, "CommonValues")
    if maxgen is not None:
        mg = el(cv, "MaxGeneration")
        el(mg, "Value", maxgen)
    lf = el(cv, "Life")
    el(lf, "Center", life[0])
    el(lf, "Max", life[1])
    el(lf, "Min", life[2])
    if gentime is not None:
        gt = el(cv, "GenerationTime")
        el(gt, "Center", gentime)
        el(gt, "Max", gentime)
        el(gt, "Min", gentime)
    if offset is not None:
        go = el(cv, "GenerationTimeOffset")
        el(go, "Center", offset)
        el(go, "Max", offset)
        el(go, "Min", offset)
    return cv


def location_pva(node, vel=None, loc=None):
    """LocationValues Type 1 (PVA). vel/loc: dict axis -> (center, min, max)."""
    lv = el(node, "LocationValues")
    el(lv, "Type", 1)
    pva = el(lv, "PVA")
    if loc:
        l = el(pva, "Location")
        for ax, (c, mn, mx) in loc.items():
            rand3(l, ax, c, mn, mx)
    if vel:
        v = el(pva, "Velocity")
        for ax, (c, mn, mx) in vel.items():
            rand3(v, ax, c, mn, mx)
    return lv


def rotation_pva_z(node, lo=-180, hi=180):
    rv = el(node, "RotationValues")
    el(rv, "Type", 1)
    pva = el(rv, "PVA")
    r = el(pva, "Rotation")
    rand3(r, "Z", 0, lo, hi)
    return rv


def scale_single_pva(node, center, lo, hi, vel=None):
    sv = el(node, "ScalingValues")
    el(sv, "Type", 3)
    sp = el(sv, "SinglePVA")
    rand3(sp, "Scale", center, lo, hi)
    if vel is not None:
        rand3(sp, "Velocity", vel, vel, vel)
    return sv


def gen_sphere(node, radius):
    gl = el(node, "GenerationLocationValues")
    el(gl, "EffectsRotation", "True")
    el(gl, "Type", 1)
    sp = el(gl, "Sphere")
    rand3(sp, "Radius", radius, radius, radius)
    rx = el(sp, "RotationX")
    el(rx, "Max", 180)
    el(rx, "Min", -180)
    ry = el(sp, "RotationY")
    el(ry, "Max", 180)
    el(ry, "Min", -180)
    return gl


def renderer(node, texture=None, blend=2, fadein=None, fadeout=None):
    rc = el(node, "RendererCommonValues")
    if texture:
        el(rc, "ColorTexture", texture)
    el(rc, "AlphaBlend", blend)
    if fadein is not None:
        el(rc, "FadeInType", 1)
        fi = el(rc, "FadeIn")
        el(fi, "Frame", fadein)
    if fadeout is not None:
        el(rc, "FadeOutType", 1)
        fo = el(rc, "FadeOut")
        el(fo, "Frame", fadeout)
    return rc


def sprite(node, color=None, billboard=2):
    dv = el(node, "DrawingValues")
    sp = el(dv, "Sprite")
    el(sp, "Billboard", billboard)
    if color:
        el(sp, "ColorAll", 1)
        cr = el(sp, "ColorAll_Random")
        for ch, (c, mn, mx) in color.items():
            rand3(cr, ch, c, mn, mx)
    return dv


def ring(node, center_color, inner_color, center_ratio="0.55"):
    dv = el(node, "DrawingValues")
    el(dv, "Type", 4)
    rg = el(dv, "Ring")
    el(rg, "VertexCount", 48)
    inf = el(rg, "Inner_Fixed")
    loc = el(inf, "Location")
    el(loc, "X", 0)
    el(rg, "CenterRatio_Fixed", center_ratio)
    cc = el(rg, "CenterColor_Fixed")
    for ch, v in center_color.items():
        el(cc, ch, v)
    ic = el(rg, "InnerColor_Fixed")
    for ch, v in inner_color.items():
        el(ic, ch, v)
    return dv


def node(parent, name, children=None):
    n = el(parent, "Node")
    el(n, "Name", name)
    if children is not None:
        ch = el(n, "Children")
        for c in children:
            ch.append(c)
    else:
        el(n, "Children")
    return n


def build_project(root_life, nodes, end_frame):
    proj = ET.Element("EffekseerProject")
    root = el(proj, "Root")
    el(root, "Name", "Root")
    kids = el(root, "Children")
    # container node (holds the effect's own life, like hit_eff's root child)
    cont = ET.Element("Node")
    common(cont, (root_life, root_life, root_life))
    dv = el(cont, "DrawingValues")
    el(dv, "Type", 0)
    el(cont, "Name", "Root")
    ch = el(cont, "Children")
    for nd in nodes:
        ch.append(nd)
    kids.append(cont)
    beh = el(proj, "Behavior")
    el(beh, "Distance", 1)
    tl = el(beh, "TargetLocation")
    el(tl, "Y", 25)
    el(proj, "ToolVersion", "1.43")
    el(proj, "Version", 3)
    el(proj, "StartFrame", 0)
    el(proj, "EndFrame", end_frame)
    el(proj, "IsLoop", "False")
    return proj


def write_xml(proj, path):
    raw = ET.tostring(proj, encoding="utf-8")
    pretty = minidom.parseString(raw).toprettyxml(indent="  ", encoding="utf-8")
    # minidom adds its own xml declaration; keep it, strip blank lines
    lines = [ln for ln in pretty.decode("utf-8").splitlines() if ln.strip()]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------- effects
def mage_orb_impact():
    nodes = []

    flash = ET.Element("Node")
    common(flash, (8, 8, 8), maxgen=1, gentime=0.01, offset=0)
    scale_single_pva(flash, 2.0, 2.0, 2.0, vel=0.35)
    renderer(flash, "Texture/particle_soft.png", blend=2, fadeout=6)
    sprite(flash, {"R": (200, 200, 200), "G": (240, 240, 240),
                   "B": (255, 255, 255), "A": (255, 255, 255)})
    el(flash, "Name", "CoreFlash")
    el(flash, "Children")
    nodes.append(flash)

    shards = ET.Element("Node")
    common(shards, (20, 25, 15), maxgen=24, gentime=0.05, offset=1)
    location_pva(shards, vel={"X": (0, -5, 5), "Y": (0, -5, 5),
                              "Z": (0, -5, 5)})
    rotation_pva_z(shards)
    scale_single_pva(shards, 0.35, 0.2, 0.5, vel=-0.01)
    gen_sphere(shards, 0.5)
    renderer(shards, "Texture/particle_soft.png", blend=2,
             fadein=2, fadeout=10)
    sprite(shards, {"R": (90, 60, 120), "G": (170, 140, 200),
                    "B": (255, 230, 255), "A": (255, 255, 255)})
    el(shards, "Name", "CyanShards")
    el(shards, "Children")
    nodes.append(shards)

    embers = ET.Element("Node")
    common(embers, (30, 35, 25), maxgen=12, gentime=0.05, offset=2)
    location_pva(embers, vel={"X": (0, -1, 1), "Y": (1.75, 1, 2.5),
                              "Z": (0, -1, 1)})
    rotation_pva_z(embers)
    scale_single_pva(embers, 0.3, 0.2, 0.45, vel=-0.005)
    gen_sphere(embers, 0.4)
    renderer(embers, "Texture/particle_soft.png", blend=2,
             fadein=3, fadeout=14)
    sprite(embers, {"R": (255, 255, 255), "G": (175, 150, 200),
                    "B": (70, 40, 100), "A": (255, 255, 255)})
    el(embers, "Name", "AmberEmbers")
    el(embers, "Children")
    nodes.append(embers)

    ringn = ET.Element("Node")
    common(ringn, (14, 14, 14), maxgen=1, gentime=0.01, offset=1)
    scale_single_pva(ringn, 0.6, 0.6, 0.6, vel=0.45)
    renderer(ringn, None, blend=2, fadeout=10)
    ring(ringn, {"G": 220, "B": 255, "A": 40},
         {"G": 240, "B": 255, "A": 180})
    el(ringn, "Name", "ShockRing")
    el(ringn, "Children")
    nodes.append(ringn)

    return build_project(40, nodes, 40)


def enemy_death_poof():
    nodes = []

    smoke = ET.Element("Node")
    common(smoke, (45, 55, 35), maxgen=10, gentime=0.3, offset=0)
    location_pva(smoke, vel={"X": (0, -0.4, 0.4), "Y": (0.65, 0.4, 0.9),
                             "Z": (0, -0.4, 0.4)})
    rotation_pva_z(smoke)
    scale_single_pva(smoke, 0.9, 0.6, 1.2, vel=0.05)
    gen_sphere(smoke, 0.6)
    renderer(smoke, "Texture/smoke_puff.png", blend=1,
             fadein=8, fadeout=25)
    sprite(smoke, {"R": (150, 130, 170), "G": (150, 130, 170),
                   "B": (150, 130, 170), "A": (200, 160, 220)})
    el(smoke, "Name", "Smoke")
    el(smoke, "Children")
    nodes.append(smoke)

    embers = ET.Element("Node")
    common(embers, (28, 34, 22), maxgen=14, gentime=0.05, offset=1)
    location_pva(embers, vel={"X": (0, -1.5, 1.5), "Y": (1.8, 1.2, 2.4),
                              "Z": (0, -1.5, 1.5)})
    rotation_pva_z(embers)
    scale_single_pva(embers, 0.28, 0.15, 0.4, vel=-0.008)
    gen_sphere(embers, 0.5)
    renderer(embers, "Texture/particle_soft.png", blend=2, fadeout=14)
    sprite(embers, {"R": (255, 255, 255), "G": (140, 110, 170),
                    "B": (50, 20, 80), "A": (255, 255, 255)})
    el(embers, "Name", "Embers")
    el(embers, "Children")
    nodes.append(embers)

    flash = ET.Element("Node")
    common(flash, (6, 6, 6), maxgen=1, gentime=0.01, offset=0)
    scale_single_pva(flash, 2.2, 2.2, 2.2, vel=0.3)
    renderer(flash, "Texture/particle_soft.png", blend=2, fadeout=4)
    sprite(flash, {"R": (255, 255, 255), "G": (200, 200, 200),
                   "B": (120, 120, 120), "A": (255, 255, 255)})
    el(flash, "Name", "Flash")
    el(flash, "Children")
    nodes.append(flash)

    return build_project(60, nodes, 60)


def main():
    out = os.path.join(HERE)
    for effect, builder in (("mage_orb_impact", mage_orb_impact),
                            ("enemy_death_poof", enemy_death_poof)):
        d = os.path.join(out, effect)
        tex = os.path.join(d, "Texture")
        os.makedirs(tex, exist_ok=True)
        soft_blob(64).save(os.path.join(tex, "particle_soft.png"))
        if effect == "enemy_death_poof":
            smoke_puff(128).save(os.path.join(tex, "smoke_puff.png"))
        write_xml(builder(), os.path.join(d, effect + ".efkproj"))
        print("wrote", effect)


if __name__ == "__main__":
    main()
