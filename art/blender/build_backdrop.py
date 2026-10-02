"""Distant dark-fantasy backdrop for Blackoff (one GLB, flat materials).

Run:  /opt/blender-venv/bin/python art/blender/build_backdrop.py [--preview DIR]
Output: client/assets/models/backdrop.glb with nodes:
  Mountains   jagged peak ring around the map (radius 150-260 m), snow on the tops
  CastleHill  gothic castle with red-lit windows on a rocky hill
  GiantHand   a stone hand rising from the ground, holding a small castle in its palm
  Pine        one conifer (the game scatters it with a MultiMesh)
Seen only from far away, so plain colours instead of textures. Origins at the
base centre; front (towards the map) is +Y (Godot -Z), like the other kits.
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
from kit import Kit  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "client", "assets", "models", "backdrop.glb")

CATS = ["rock", "snow", "stone", "roof", "pine", "bark", "e_window", "e_violet"]
ROCK, SNOW, STONE, ROOF, PINE, BARK, E_WINDOW, E_VIOLET = range(len(CATS))
COLORS = {ROCK: "#3a3d4f", SNOW: "#aab4d6", STONE: "#4a4a58", ROOF: "#2a2433", PINE: "#1b2a2c", BARK: "#2b2220"}
EMIT = {E_WINDOW: ("#ff6a2a", 7.0), E_VIOLET: ("#b56bff", 5.0)}


def noise1(x, seed):
    """Smooth 1D value noise."""
    i = math.floor(x)
    f = x - i
    f = f * f * (3 - 2 * f)
    a = random.Random(seed * 1000003 + i).random()
    b = random.Random(seed * 1000003 + i + 1).random()
    return a + (b - a) * f


def mountains(k):
    n = "Mountains"
    seg, rings = 160, 10
    r0, r1 = 150.0, 260.0
    bm = bmesh.new()
    rows = []
    for j in range(rings + 1):
        t = j / rings
        r = r0 + (r1 - r0) * t
        row = []
        for i in range(seg):
            a = i / seg * math.tau
            ridge = sum(abs(noise1(a * f * 6 + j * 0.15, 3 + o) - 0.5) * 2 * amp
                        for o, (f, amp) in enumerate(((1, 1.0), (2.3, 0.5), (5.1, 0.25))))
            h = (1 - ridge / 1.75) ** 2 * 90 * math.sin(t * math.pi) ** 0.7 + noise1(a * 40, 9) * 6
            h *= 1 - 0.45 * math.exp(-((a - math.pi / 2) / 0.6) ** 2)  # lower behind the castles (north)
            if j in (0, rings):
                h = -4
            row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, h)))
        rows.append(row)
    for j in range(rings):
        for i in range(seg):
            i2 = (i + 1) % seg
            bm.faces.new((rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(n)
    bm.to_mesh(me)
    bm.free()
    ob = lib.link(bpy.data.objects.new(n, me))
    k._finish(ob, n, ROCK, 0.0, smooth_angle=60)
    for p in ob.data.polygons:  # snow caps
        if p.center.z > 52 and p.normal.z > 0.45:
            p.material_index = SNOW


def rock_mound(k, n, c, radius, height, seed):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=c)
    ob = bpy.context.active_object
    rnd = random.Random(seed)
    for v in ob.data.vertices:
        d = v.co.normalized()
        bump = 1 + 0.18 * math.sin(d.x * 7 + seed) * math.cos(d.y * 5) + rnd.uniform(-0.06, 0.06)
        v.co = Vector((d.x * radius * bump, d.y * radius * bump, max(d.z, -0.1) * height * bump))
    return k._finish(ob, n, ROCK, 0.0, smooth_angle=40)


def castle(k, n, base, s, seed):
    """Gothic castle: keep, corner towers with spires, curtain walls, lit windows."""
    rnd = random.Random(seed)
    b = Vector(base)

    def P(x, y, z):
        return b + Vector((x, y, z)) * s

    def tower(x, y, r, h, roof_h, windows=4):
        k.cyl(n, STONE, P(x, y, 0), P(x, y, h), r * s, 10, 0.0)
        k.cyl(n, STONE, P(x, y, h), P(x, y, h + 0.8), r * 1.15 * s, 10, 0.0)
        k.cyl(n, ROOF, P(x, y, h + 0.8), P(x, y, h + 0.8 + roof_h), r * 1.2 * s, 10, 0.0, r2=0.0)
        for w in range(windows):
            z = h * (0.3 + 0.6 * w / max(windows - 1, 1))
            if rnd.random() < 0.8:
                a = rnd.uniform(-0.7, 0.7) + math.pi / 2  # face the map (+Y)
                k.box(n, E_WINDOW, P(x + math.cos(a) * r * 1.01, y + math.sin(a) * r * 1.01, z),
                      Vector((0.9, 0.4, 1.8)) * s, 0.0, rot=(0, 0, math.degrees(a) - 90))

    # keep
    k.box(n, STONE, P(0, 0, 13), Vector((16, 14, 26)) * s, 0.0)
    for x in range(-6, 7, 3):
        for z in (8, 13, 18, 23):
            if rnd.random() < 0.55:
                k.box(n, E_WINDOW, P(x, 7.05, z), Vector((1.0, 0.3, 2.2)) * s, 0.0)
    k.cyl(n, ROOF, P(0, 0, 26), P(0, 0, 34), 9 * s, 4, 0.0, r2=0.0)
    tower(0, 0, 3.0, 40, 16, 5)                                     # central spire
    for sx in (-1, 1):
        for sy in (-1, 1):
            tower(sx * 9, sy * 8, 3.2, 30 + rnd.uniform(-3, 4), 11)
        tower(sx * 22, 10, 2.4, 20, 8, 3)                          # outer wall towers
        tower(sx * 4.5, 8.5, 1.6, 33, 9, 2)                         # thin spires
    # curtain wall with crenellations
    for x0, x1, y in ((-22, 22, 10),):
        k.box(n, STONE, P((x0 + x1) / 2, y, 6), Vector((x1 - x0, 2.5, 12)) * s, 0.0)
        for x in range(x0, x1 + 1, 2):
            k.box(n, STONE, P(x, y, 12.6), Vector((1.0, 2.5, 1.2)) * s, 0.0)
    k.box(n, E_WINDOW, P(0, 11.3, 3.5), Vector((3.2, 0.3, 7.0)) * s, 0.0)  # glowing gate


def castle_hill(k):
    n = "CastleHill"
    rock_mound(k, n, (0, 0, 0), 42, 26, 5)
    castle(k, n, (0, 0, 22), 1.0, 7)


def giant_hand(k):
    """Stone hand rising out of the ground, palm up, cradling a castle."""
    n = "GiantHand"
    rock_mound(k, n, (0, 0, 0), 30, 10, 2)
    k.cyl(n, ROCK, (0, 0, -2), (0, -3, 46), 13, 14, 0.0, r2=10)           # forearm
    k.sphere(n, ROCK, (0, -3, 52), 15, scale=(1.2, 0.75, 0.55), segs=16)   # palm
    # fingers: 4 curled up around the palm, plus the thumb
    fingers = [(-13, -1.5, 0.0), (-4.5, -2.0, 0.0), (4.5, -2.0, 0.0), (13, -1.5, 0.0)]
    for i, (x, y, _) in enumerate(fingers):
        p = Vector((x * 1.05, y - 9, 54))
        d = Vector((x * 0.025, -0.12, 1.0)).normalized()
        r = 3.8 - abs(i - 1.5) * 0.4
        length = 34 - abs(i - 1.5) * 6
        for seg in range(3):
            q = p + d * length * (0.4, 0.33, 0.27)[seg]
            k.cyl(n, ROCK, p, q, r, 10, 0.0, r2=r * 0.86)
            k.sphere(n, ROCK, q, r * 0.88, segs=10)
            d = (d + Vector((0, 0.32, -0.02))).normalized()  # claw-like curl over the palm
            p, r = q, r * 0.86
        k.cyl(n, ROCK, p, p + d * r * 1.6, r * 0.8, 8, 0.0, r2=0.2)  # pointed nail
    p = Vector((-17, 2, 50))
    d = Vector((-0.4, 0.6, 0.7)).normalized()
    r = 4.2
    for seg in range(2):
        q = p + d * 9
        k.cyl(n, ROCK, p, q, r, 10, 0.0, r2=r * 0.85)
        k.sphere(n, ROCK, q, r * 0.85, segs=10)
        d = (d + Vector((0.6, 0.3, 0.2))).normalized()
        p, r = q, r * 0.85
    castle(k, n, (0, -3, 58), 0.42, 11)
    for i in range(6):  # violet glow seeping between the fingers
        a = i / 6 * math.tau
        k.sphere(n, E_VIOLET, (math.cos(a) * 12, -3 + math.sin(a) * 7, 55), 1.4, segs=8)


def pine(k):
    n = "Pine"
    k.cyl(n, BARK, (0, 0, 0), (0, 0, 3), 0.35, 6, 0.0, r2=0.25)
    for i, (z, r, h) in enumerate(((2.0, 3.2, 5.0), (4.5, 2.6, 4.5), (7.0, 1.9, 4.0), (9.3, 1.2, 3.6))):
        k.cyl(n, PINE, (0, 0, z), (0, 0, z + h), r, 7, 0.0, r2=0.05)


def build():
    lib.reset()
    k = Kit(CATS)
    parts = {}
    for name, fn in (("Mountains", mountains), ("CastleHill", castle_hill), ("GiantHand", giant_hand), ("Pine", pine)):
        before = len(k.parts)
        fn(k)
        parts[name] = k.parts[before:]
    mats = {i: lib.flat_material("bd_" + CATS[i], COLORS[i], roughness=0.9) for i in COLORS}
    mats.update({i: lib.flat_material("bd_" + CATS[i], hx, emission=hx, strength=st) for i, (hx, st) in EMIT.items()})
    nodes = {}
    for name, objs in parts.items():
        ob = lib.join(objs, name) if len(objs) > 1 else objs[0]
        ob.name = name
        for g in list(ob.vertex_groups):
            ob.vertex_groups.remove(g)
        lib.activate(ob)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        for i in range(len(ob.data.materials)):
            ob.data.materials[i] = mats[i]
        nodes[name] = ob
        print("  %-12s %6d tris" % (name, lib.tri_count(ob)))
    return nodes


def main():
    nodes = build()
    lib.activate(*nodes.values())
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=False)
    if "--preview" in sys.argv:
        d = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        nodes["CastleHill"].location = (-60, 175, 0)
        nodes["GiantHand"].location = (75, 190, 0)
        nodes["Pine"].location = (5, 40, 0)
        lib.render_setup((1600, 900), samples=24)
        bpy.context.scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.08, 0.25, 1)
        bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
        lib.add_camera((0, -20, 8), (0, 180, 40), lens=22)
        lib.add_light('SUN', (0, 0, 10), 2.5, (0.7, 0.7, 1.0), rot=(math.radians(55), 0, math.radians(200)))
        bpy.context.scene.render.film_transparent = False
        bpy.context.scene.camera.data.clip_end = 1000
        lib.render(os.path.join(d, "backdrop.png"))


if __name__ == "__main__":
    main()
