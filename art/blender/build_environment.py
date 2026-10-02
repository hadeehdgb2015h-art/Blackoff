"""Facility prop kit for Blackoff (one GLB, one shared texture atlas).

Run:  /opt/blender-venv/bin/python art/blender/build_environment.py [--preview DIR]
Output: client/assets/models/env_props.glb
Each prop is a named node with its origin at floor centre, front facing +Y
(Godot -Z). Emissive parts (screens, tanks, crystals, lamps) use separate
emissive materials so they glow (and bloom) in game. Palette: readable
mid-values with dark-fantasy accents (teal, violet, amber, crimson).
"""
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
import painter as pt  # noqa: E402
from kit import Kit  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "client", "assets", "models", "env_props.glb")
TEX = 2048

CATS = ["steel", "paint_teal", "paint_red", "paint_yellow", "plastic_violet", "wood", "canvas", "concrete",
        "rubber", "hazard", "brass", "e_teal", "e_violet", "e_warm", "e_red", "e_green", "e_white", "glass"]
(STEEL, TEAL, RED, YELLOW, VIOLET, WOOD, CANVAS, CONCRETE, RUBBER, HAZARD, BRASS,
 E_TEAL, E_VIOLET, E_WARM, E_RED, E_GREEN, E_WHITE, GLASS) = range(len(CATS))
EMISSIVE = {E_TEAL: "#19c9b3", E_VIOLET: "#a24bff", E_WARM: "#ffb257", E_RED: "#ff3b30", E_GREEN: "#58ff7a", E_WHITE: "#dfe8ff"}

PROPS = []  # (name, builder)


def prop(fn):
    PROPS.append((fn.__name__[0].upper() + fn.__name__[1:], fn))
    return fn


# ---------------------------------------------------------------- props (built at origin, +Y front)

def _barrel(k, n, paint):
    k.cyl(n, paint, (0, 0, 0.0), (0, 0, 0.88), 0.29, 24, 0.006)
    for z in (0.29, 0.59):
        k.cyl(n, paint, (0, 0, z - 0.015), (0, 0, z + 0.015), 0.302, 24, 0.004)
    k.cyl(n, STEEL, (0, 0, 0.86), (0, 0, 0.9), 0.296, 24, 0.004)
    k.cyl(n, STEEL, (0.15, 0.05, 0.9), (0.15, 0.05, 0.915), 0.03, 10, 0.002)
    k.box(n, HAZARD, (0, 0.287, 0.46), (0.22, 0.012, 0.16), 0.002)


@prop
def barrel(k):
    _barrel(k, "Barrel", RED)


@prop
def barrelChem(k):
    _barrel(k, "BarrelChem", VIOLET)
    k.cyl("BarrelChem", E_GREEN, (0.12, 0.2, 0.9), (0.12, 0.2, 0.905), 0.08, 12, 0)  # glowing spill on the lid


@prop
def crate(k):
    n = "Crate"
    k.box(n, WOOD, (0, 0, 0.3), (1.0, 0.6, 0.6), 0.01)
    for x in (-0.46, 0.46):
        for z in (0.04, 0.56):
            k.box(n, STEEL, (x, 0, z), (0.1, 0.62, 0.1), 0.004)
    k.box(n, HAZARD, (0.25, 0.302, 0.36), (0.3, 0.004, 0.12), 0.001)


@prop
def lockers(k):
    n = "Lockers"
    for i in range(3):
        x = (i - 1) * 0.51
        k.box(n, TEAL, (x, 0, 0.95), (0.5, 0.5, 1.9), 0.008)
        door = k.box(n, TEAL, (x, 0.252, 1.0), (0.44, 0.012, 1.7), 0.004)
        k.cut(door, [k.box("cut", TEAL, (x, 0.258, 1.55 + j * 0.035), (0.3, 0.02, 0.012), 0) for j in range(5)])
        k.box(n, STEEL, (x + 0.16, 0.262, 1.0), (0.025, 0.02, 0.14), 0.003)
        k.box(n, HAZARD, (x - 0.08, 0.262, 1.82), (0.14, 0.004, 0.05), 0.001)
    k.box(n, STEEL, (0, 0, 0.03), (1.56, 0.52, 0.06), 0.004)


@prop
def console(k):
    n = "Console"
    k.box(n, TEAL, (0, 0, 0.38), (0.95, 0.6, 0.76), 0.01)
    k.prism(n, STEEL, [(-0.3, 0.76), (0.3, 0.76), (0.3, 0.86), (-0.12, 1.08), (-0.3, 1.08)], 0.95, bevel=0.008)
    k.box(n, E_TEAL, (0, 0.11, 0.97), (0.7, 0.004, 0.14), 0, rot=(-62, 0, 0))
    for i in range(6):
        k.box(n, E_RED if i % 3 == 0 else E_GREEN, (-0.35 + i * 0.14, 0.22, 0.83), (0.04, 0.03, 0.012), 0.002, rot=(-28, 0, 0))
    k.box(n, STEEL, (0, -0.12, 1.32), (0.62, 0.12, 0.42), 0.012)                 # monitor
    k.box(n, E_TEAL, (0, -0.058, 1.33), (0.54, 0.004, 0.34), 0)
    k.box(n, STEEL, (0, -0.2, 1.1), (0.08, 0.08, 0.06), 0.006)


@prop
def tank(k):
    n = "Tank"
    k.cyl(n, STEEL, (0, 0, 0), (0, 0, 0.28), 0.5, 24, 0.01)
    k.cyl(n, STEEL, (0, 0, 2.12), (0, 0, 2.36), 0.5, 24, 0.01)
    k.cyl(n, E_TEAL, (0, 0, 0.28), (0, 0, 2.12), 0.4, 24, 0)
    for i in range(6):
        a = i / 6 * math.tau
        k.cyl(n, STEEL, (math.cos(a) * 0.44, math.sin(a) * 0.44, 0.28), (math.cos(a) * 0.44, math.sin(a) * 0.44, 2.12), 0.025, 8, 0.002)
    k.cyl(n, STEEL, (0, 0, 2.36), (0, 0, 2.9), 0.08, 12, 0.004)
    k.box(n, HAZARD, (0, 0.5, 0.14), (0.4, 0.01, 0.1), 0.001)
    # silhouette of something suspended inside
    k.cyl(n, CONCRETE, (0, 0, 0.7), (0, 0, 1.55), 0.12, 10, 0.01)
    k.sphere(n, CONCRETE, (0, 0.01, 1.68), 0.1)


@prop
def labTable(k):
    n = "LabTable"
    k.box(n, STEEL, (0, 0, 0.9), (1.8, 0.8, 0.05), 0.006)
    for x in (-0.84, 0.84):
        for y in (-0.34, 0.34):
            k.box(n, STEEL, (x, y, 0.45), (0.05, 0.05, 0.88), 0.003)
    k.box(n, STEEL, (0, 0, 0.22), (1.7, 0.72, 0.03), 0.004)
    for i, (x, c) in enumerate(((-0.6, E_TEAL), (-0.45, E_VIOLET), (-0.32, E_GREEN), (0.55, E_TEAL))):
        k.cyl(n, GLASS, (x, 0.1, 0.925), (x, 0.1, 1.08), 0.045, 12, 0.002)
        k.cyl(n, c, (x, 0.1, 0.93), (x, 0.1, 1.02), 0.04, 12, 0)
    k.box(n, TEAL, (0.15, -0.1, 1.05), (0.4, 0.35, 0.25), 0.01)                   # analyser
    k.box(n, E_GREEN, (0.15, 0.077, 1.08), (0.25, 0.004, 0.1), 0)
    for i in range(3):
        k.box(n, HAZARD, (0.6 + i * 0.05, -0.15, 0.93), (0.21, 0.29, 0.004), 0, rot=(0, 0, 8 * i - 8))


@prop
def shelf(k):
    n = "Shelf"
    for x in (-0.97, 0.97):
        for y in (-0.22, 0.22):
            k.box(n, STEEL, (x, y, 1.0), (0.05, 0.05, 2.0), 0.003)
    rnd = random.Random(5)
    for z in (0.15, 0.7, 1.25, 1.8):
        k.box(n, STEEL, (0, 0, z), (2.0, 0.5, 0.03), 0.003)
        x = -0.85
        while x < 0.8:
            w = rnd.uniform(0.2, 0.45)
            h = rnd.uniform(0.15, 0.4)
            k.box(n, CANVAS if rnd.random() < 0.6 else WOOD, (x + w / 2, rnd.uniform(-0.05, 0.05), z + 0.015 + h / 2), (w, 0.38, h), 0.006)
            x += w + 0.06


@prop
def generator(k):
    n = "Generator"
    k.box(n, YELLOW, (0, 0, 0.55), (1.6, 0.9, 0.9), 0.02)
    k.box(n, STEEL, (0, 0, 0.05), (1.7, 1.0, 0.1), 0.006)
    cut = k.box(n, YELLOW, (0.45, 0, 0.6), (0.5, 0.92, 0.5), 0.0)
    k.parts.remove(cut)
    bpy.data.objects.remove(cut, do_unlink=True)
    for i in range(7):
        k.box(n, STEEL, (0.45, 0.455, 0.42 + i * 0.05), (0.5, 0.01, 0.02), 0.002)
    k.box(n, STEEL, (-0.4, 0.46, 0.65), (0.4, 0.02, 0.3), 0.006)
    for i, c in enumerate((E_GREEN, E_RED, E_WARM)):
        k.sphere(n, c, (-0.52 + i * 0.12, 0.475, 0.72), 0.018)
    k.cyl(n, STEEL, (-0.6, -0.3, 1.0), (-0.6, -0.3, 1.5), 0.06, 12, 0.003)
    k.box(n, HAZARD, (0, 0.452, 0.18), (1.4, 0.006, 0.08), 0.001)


@prop
def sandbags(k):
    n = "Sandbags"
    rnd = random.Random(3)
    for layer in range(3):
        count = 5 - (layer == 2)
        for i in range(count):
            x = (i - (count - 1) / 2) * 0.42 + (0.21 if layer == 1 else 0)
            k.sphere(n, CANVAS, (x, rnd.uniform(-0.02, 0.02), 0.1 + layer * 0.19), 0.12,
                     scale=(1.8, 1.25, 0.85), segs=10)


@prop
def lampPost(k):
    n = "LampPost"
    k.box(n, CONCRETE, (0, 0, 0.15), (0.4, 0.4, 0.3), 0.02)
    k.cyl(n, STEEL, (0, 0, 0.3), (0, 0, 4.0), 0.06, 12, 0.004, r2=0.045)
    k.cyl(n, STEEL, (0, 0, 3.95), (0, 0.6, 4.05), 0.035, 10, 0.003)
    k.box(n, STEEL, (0, 0.72, 4.0), (0.3, 0.38, 0.1), 0.01)
    k.box(n, E_WARM, (0, 0.72, 3.945), (0.24, 0.3, 0.012), 0)


def _wall_lamp(k, n, emit):
    k.box(n, STEEL, (0, 0.02, 0), (0.22, 0.04, 0.22), 0.006)
    k.cyl(n, STEEL, (0, 0.04, 0), (0, 0.1, 0), 0.05, 12, 0.003)
    k.sphere(n, emit, (0, 0.14, 0), 0.06)
    for a in range(4):
        ang = a / 4 * math.pi
        k.cyl(n, STEEL, (math.cos(ang) * 0.085, 0.08, math.sin(ang) * 0.085), (math.cos(ang) * 0.085, 0.2, math.sin(ang) * 0.085), 0.006, 6, 0)
    k.cyl(n, STEEL, (0, 0.2, 0), (0, 0.21, 0), 0.09, 12, 0.002)


@prop
def wallLampWarm(k):
    _wall_lamp(k, "WallLampWarm", E_WARM)


@prop
def wallLampTeal(k):
    _wall_lamp(k, "WallLampTeal", E_TEAL)


@prop
def wallLampViolet(k):
    _wall_lamp(k, "WallLampViolet", E_VIOLET)


@prop
def ceilingLamp(k):
    n = "CeilingLamp"
    k.box(n, STEEL, (0, 0, -0.04), (1.3, 0.24, 0.08), 0.008)
    k.box(n, E_WHITE, (0, 0, -0.082), (1.2, 0.16, 0.006), 0)
    for x in (-0.5, 0.5):
        k.cyl(n, STEEL, (x, 0, 0.0), (x, 0, 0.25), 0.006, 6, 0)


@prop
def pipe(k):
    n = "Pipe"
    k.cyl(n, STEEL, (-1.0, 0, 0), (1.0, 0, 0), 0.07, 14, 0.004)
    for x in (-0.98, 0.98):
        k.cyl(n, STEEL, (x - 0.025, 0, 0), (x + 0.025, 0, 0), 0.095, 14, 0.004)
    k.box(n, STEEL, (0, -0.12, 0), (0.06, 0.2, 0.04), 0.003)        # wall bracket (back = -Y)
    k.cyl(n, RED, (0.4, 0, 0), (0.55, 0, 0), 0.072, 14, 0)          # flow marking band


def _crystals(k, n, scale, seed):
    rnd = random.Random(seed)
    k.sphere(n, CONCRETE, (0, 0, 0.0), 0.55 * scale, scale=(1.4, 1.2, 0.5), segs=12)
    for i in range(9):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.0, 0.45) * scale
        base = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
        h = rnd.uniform(0.6, 2.2) * scale * (1.0 if i else 1.25)
        tilt = Vector((rnd.uniform(-0.35, 0.35), rnd.uniform(-0.35, 0.35), 1.0)).normalized()
        w = rnd.uniform(0.07, 0.16) * scale
        k.cyl(n, E_VIOLET, base, base + tilt * h * 0.8, w, 6, 0.0, r2=w * 0.85)
        k.cyl(n, E_VIOLET, base + tilt * h * 0.8, base + tilt * h, w * 0.85, 6, 0.0, r2=0.001)


@prop
def crystals(k):
    _crystals(k, "Crystals", 1.0, 11)


@prop
def crystalsSmall(k):
    _crystals(k, "CrystalsSmall", 0.45, 12)


@prop
def rubble(k):
    n = "Rubble"
    rnd = random.Random(8)
    for i in range(14):
        s = rnd.uniform(0.08, 0.3)
        k.box(n, CONCRETE, (rnd.uniform(-0.6, 0.6), rnd.uniform(-0.4, 0.4), s * 0.35), (s * 1.3, s, s * 0.7), 0.01,
              rot=(rnd.uniform(-20, 20), rnd.uniform(-20, 20), rnd.uniform(0, 180)))


def _door_frame(k, n, width):
    hw = width / 2
    for sx in (-1, 1):
        k.box(n, STEEL, (sx * (hw + 0.07), 0, 1.3), (0.14, 0.42, 2.6), 0.01)
    k.box(n, STEEL, (0, 0, 2.66), (width + 0.28, 0.42, 0.12), 0.01)
    k.box(n, TEAL, (0, 0, 2.86), (width + 0.02, 0.3, 0.28), 0.004)       # header infill up to the 3 m ceiling
    for sy in (-1, 1):
        k.box(n, HAZARD, (0, sy * 0.212, 2.66), (width + 0.2, 0.004, 0.08), 0.001)
    k.box(n, E_RED, (hw - 0.12, 0.215, 2.78), (0.1, 0.01, 0.06), 0.002)   # status light over the door


@prop
def doorFrame2(k):
    _door_frame(k, "DoorFrame2", 2.0)


@prop
def doorFrame25(k):
    _door_frame(k, "DoorFrame25", 2.5)


# ---------------------------------------------------------------- painting

def paint(P, part, edges, seed):
    N = len(P)
    n1 = pt.fbm(P, 9, 4, seed)
    n2 = pt.fbm(P, 40, 3, seed + 3)
    wear = pt.smooth(0.5, 0.95, edges)  # only the sharpest convex edges
    grime = pt.smooth(0.55, 0.85, pt.fbm(P, 4, 3, seed + 7))
    col = np.zeros((N, 3), np.float32)
    rough = np.full(N, 0.7, np.float32)
    metal = np.zeros(N, np.float32)

    def painted(c1, c2, chip_to="#6d6f73"):
        c = pt.lerp(pt.hexc(c1), pt.hexc(c2), n1)
        chips = pt.smooth(0.72, 0.78, pt.fbm(P, 22, 3, seed + 11))
        c = pt.lerp(c, pt.hexc(chip_to), np.clip(wear * 0.8 + chips * 0.6, 0, 1))
        return pt.lerp(c, pt.hexc("#2a2622"), grime * 0.35)

    steel = pt.lerp(pt.hexc("#4a4c50"), pt.hexc("#2f3134"), n1)
    steel = pt.lerp(steel, pt.hexc("#8b8f94"), wear * 0.6)
    steel = pt.lerp(steel, pt.hexc("#5e3a24"), pt.smooth(0.65, 0.85, pt.fbm(P, 12, 3, seed + 5)) * 0.45)
    table = {
        STEEL: (steel, 0.45, 0.8),
        TEAL: (painted("#3f6f72", "#2f5558"), 0.6, 0.2),
        RED: (painted("#7a3329", "#5a241e"), 0.6, 0.2),
        YELLOW: (painted("#c29a2e", "#9c7a22"), 0.55, 0.2),
        VIOLET: (pt.lerp(pt.hexc("#5d3f80"), pt.hexc("#432c5e"), n1), 0.45, 0.0),
        WOOD: (pt.lerp(pt.hexc("#86643f"), pt.hexc("#5c4329"), np.clip(n1 * 0.6 + 0.4 * (np.sin(P[:, 2] * 60 + n2 * 6) * 0.5 + 0.5), 0, 1)), 0.8, 0.0),
        CANVAS: (pt.lerp(pt.hexc("#958865"), pt.hexc("#6f6449"), n1) * (0.94 + 0.06 * np.sin(P[:, 0] * 500) * np.sin(P[:, 2] * 500))[:, None], 0.9, 0.0),
        CONCRETE: (pt.lerp(pt.hexc("#7a7672"), pt.hexc("#55524f"), n1), 0.9, 0.0),
        RUBBER: (pt.lerp(pt.hexc("#202022"), pt.hexc("#141415"), n1), 0.85, 0.0),
        BRASS: (pt.lerp(pt.hexc("#a8853f"), pt.hexc("#7a5e2a"), n1), 0.35, 1.0),
        GLASS: (np.tile(pt.hexc("#1a2a2c"), (N, 1)), 0.05, 0.0),
    }
    stripes = (np.mod((P[:, 0] + P[:, 2]) * 8.0, 1.0) < 0.5)
    hazard = np.where(stripes[:, None], pt.hexc("#d6a422"), pt.hexc("#1b1b1b"))
    table[HAZARD] = (pt.lerp(hazard, pt.hexc("#4a4232"), grime * 0.4), 0.6, 0.0)
    for cat, (c, r, m) in table.items():
        sel = part == cat
        col[sel] = c[sel]
        rough[sel] = r
        metal[sel] = m
    return np.clip(col, 0, 1), rough, metal


def texture(ob):
    lib.activate(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(50), island_margin=0.003)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.002, shape_method='CONCAVE')
    bpy.ops.object.mode_set(mode='OBJECT')
    edges = lib.bake_pointiness(ob, TEX)
    print("    edge mask mean %.3f" % float(edges.mean()))
    ao = lib.bake_ao(ob, TEX, samples=24)
    pos, nor, part, valid = pt.rasterize(ob, TEX)
    rgb = np.zeros((TEX, TEX, 3), np.float32)
    orm = np.zeros((TEX, TEX, 3), np.float32)
    c, r, m = paint(pos[valid], part[valid], edges[valid], 23)
    rgb[valid] = c * (0.4 + 0.6 * ao[valid])[:, None]
    orm[valid] = np.stack([ao[valid], r, m], 1)
    mat = lib.pbr_material("env_props", pt.to_image(bpy, "env_props_albedo", rgb, valid),
                           pt.to_image(bpy, "env_props_orm", orm, valid, non_color=True))
    strength = {E_VIOLET: 3.0, E_WHITE: 2.6, E_WARM: 2.6, E_TEAL: 1.6, E_GREEN: 1.8, E_RED: 2.2}
    emissive = {cat: lib.flat_material("emit_" + CATS[cat], hexcol, emission=hexcol, strength=strength[cat]) for cat, hexcol in EMISSIVE.items()}
    for i in range(len(ob.data.materials)):
        ob.data.materials[i] = emissive.get(i, mat)


# ---------------------------------------------------------------- build / export

def build():
    lib.reset()
    k = Kit(CATS)
    offsets = {}
    for i, (name, fn) in enumerate(PROPS):
        before = len(k.parts)
        fn(k)
        off = Vector(((i % 6) * 4.0, (i // 6) * 4.0, 0))
        offsets[name] = off
        for o in k.parts[before:]:
            for v in o.data.vertices:
                v.co += off
    ob = lib.join(k.parts, "props")
    texture(ob)
    nodes = lib.separate_by_groups(ob, [n for n, _ in PROPS])
    for name, o in nodes.items():
        for v in o.data.vertices:
            v.co -= offsets[name]
        for g in list(o.vertex_groups):
            o.vertex_groups.remove(g)
    if ob.name not in [o.name for o in nodes.values()] and len(ob.data.vertices) == 0:
        bpy.data.objects.remove(ob, do_unlink=True)
    for name, o in nodes.items():
        print("  %-14s %5d tris" % (name, lib.tri_count(o)))
    return nodes


def main():
    nodes = build()
    lib.activate(*nodes.values())
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                              export_image_format='JPEG', export_jpeg_quality=88, export_animations=False)
    if "--preview" in sys.argv:
        d = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        for i, (name, o) in enumerate(nodes.items()):
            o.location = ((i % 6) * 3.2, -(i // 6) * 3.6, 0)
        lib.render_setup((1600, 900), samples=32)
        bpy.context.scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.08, 1)
        bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 3.0
        lib.add_camera((7.5, 9.5, 9.5), (8.0, -3.6, 0.6), lens=24)
        lib.add_light('SUN', (0, 0, 10), 3.0, (1.0, 0.92, 0.85), rot=(math.radians(50), 0, math.radians(150)))
        bpy.ops.mesh.primitive_plane_add(size=60, location=(8, -4, 0))
        lib.render(os.path.join(d, "env_props.png"))


if __name__ == "__main__":
    main()
