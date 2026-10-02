"""Dark-fantasy prop kit for Blackoff (one GLB, one shared texture atlas).

Run:  /opt/blender-venv/bin/python art/blender/build_dark_props.py [--preview DIR]
Output: client/assets/models/dark_props.glb
Same conventions as build_environment.py: one named node per prop, origin at
floor centre, front facing +Y (Godot -Z), emissive parts as separate materials.
Inspired by the owner's references: skeletons with glowing violet eyes, gothic
stone and wrought iron, candles, dead trees, braziers. No religious symbols.
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
OUT = os.path.join(ROOT, "client", "assets", "models", "dark_props.glb")
TEX = 1024

CATS = ["bone", "socket", "stone", "iron", "bark", "wax", "cloth", "gold", "coal",
        "e_flame", "e_eye", "e_ember", "e_blue"]
BONE, SOCKET, STONE, IRON, BARK, WAX, CLOTH, GOLD, COAL, E_FLAME, E_EYE, E_EMBER, E_BLUE = range(len(CATS))
EMISSIVE = {E_FLAME: ("#ffb24a", 4.0), E_EYE: ("#b46bff", 6.0), E_EMBER: ("#ff5a1f", 3.5), E_BLUE: ("#a8ccff", 4.5)}

PROPS = []


def prop(fn):
    PROPS.append((fn.__name__[0].upper() + fn.__name__[1:], fn))
    return fn


# ---------------------------------------------------------------- helpers

def torus(k, n, mat, center, major, minor, scale=(1, 1, 1), rot=(0, 0, 0), segs=16):
    bpy.ops.mesh.primitive_torus_add(major_segments=segs, minor_segments=6, major_radius=major, minor_radius=minor,
                                     location=center, rotation=[math.radians(r) for r in rot])
    ob = bpy.context.active_object
    ob.scale = scale
    return k._finish(ob, n, mat, 0, smooth_angle=80)


def bone(k, n, a, b, r, knobs=True):
    k.cyl(n, BONE, a, b, r, 8, 0.0)
    if knobs:
        for p in (a, b):
            k.sphere(n, BONE, p, r * 1.55, segs=8)


def skull(k, n, c, s=1.0, eyes=True, jaw_open=0.3):
    c = Vector(c)
    k.sphere(n, BONE, c, 0.1 * s, scale=(0.85, 1.0, 0.95), segs=14)                         # cranium
    k.sphere(n, BONE, c + Vector((0, 0.05, -0.05)) * s, 0.07 * s, scale=(0.95, 0.8, 0.8), segs=10)  # face
    k.box(n, BONE, c + Vector((0, 0.045, -0.115 - jaw_open * 0.04)) * s, Vector((0.1, 0.07, 0.03)) * s, 0.004,
          rot=(-jaw_open * 40, 0, 0))                                                         # jaw
    k.box(n, BONE, c + Vector((0, 0.1, -0.085)) * s, Vector((0.075, 0.012, 0.022)) * s, 0.002)   # teeth
    k.box(n, SOCKET, c + Vector((0, 0.112, -0.04)) * s, Vector((0.018, 0.01, 0.028)) * s, 0.002)  # nose
    for sx in (-1, 1):
        p = c + Vector((sx * 0.036, 0.085, -0.005)) * s
        k.sphere(n, E_EYE if eyes else SOCKET, p, 0.024 * s, scale=(1.1, 0.6, 0.9), segs=8)


def slab(k, n, mat, pts_xz, thick, y=0.0):
    """Flat polygon in the XZ plane, thickness along Y."""
    import bmesh
    bm = bmesh.new()
    f = [bm.verts.new((x, y - thick / 2, z)) for x, z in pts_xz]
    b = [bm.verts.new((x, y + thick / 2, z)) for x, z in pts_xz]
    bm.faces.new(f)
    bm.faces.new(list(reversed(b)))
    for i in range(len(pts_xz)):
        j = (i + 1) % len(pts_xz)
        bm.faces.new((f[i], b[i], b[j], f[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(n)
    bm.to_mesh(me)
    bm.free()
    ob = lib.link(bpy.data.objects.new(n, me))
    return k._finish(ob, n, mat, 0.0)


def flame(k, n, p, h=0.05, mat=E_FLAME):
    p = Vector(p)
    k.sphere(n, mat, p + Vector((0, 0, h * 0.5)), h * 0.32, scale=(1, 1, 1.8), segs=8)


# ---------------------------------------------------------------- props

@prop
def skeletonSit(k):
    """Slumped against a wall (behind it, -Y), legs out, glowing eyes."""
    n = "SkeletonSit"
    pel = Vector((0, 0.02, 0.14))
    torus(k, n, BONE, pel, 0.08, 0.022, scale=(1.2, 0.8, 1), rot=(20, 0, 0))                  # pelvis ring
    for sx in (-1, 1):
        k.sphere(n, BONE, pel + Vector((sx * 0.09, -0.03, 0.05)), 0.07, scale=(0.6, 0.35, 0.8), segs=10)  # iliac wings
    # spine leaning back against the wall
    top = Vector((0.0, -0.14, 0.64))
    for i in range(10):
        t = i / 9
        p = pel.lerp(top, t) + Vector((0, -0.02 * math.sin(t * math.pi), 0))
        k.cyl(n, BONE, p - Vector((0, 0, 0.018)), p + Vector((0, 0, 0.018)), 0.024, 8, 0.0)
    # rib cage: stacked elliptical rings, smaller toward the bottom
    for i in range(6):
        t = i / 5
        z = 0.6 - t * 0.2
        r = 0.13 - t * 0.03
        torus(k, n, BONE, (0, -0.07 - t * 0.02 + 0.02, z), r, 0.011, scale=(1.0, 0.72, 1.0), rot=(12, 0, 0))
    k.box(n, BONE, (0, 0.04, 0.52), (0.035, 0.02, 0.16), 0.004, rot=(-12, 0, 0))              # sternum
    torus(k, n, BONE, (0, -0.1, 0.62), 0.15, 0.014, scale=(1.15, 0.45, 1), rot=(10, 0, 0))    # collar bones
    skull(k, n, (0.03, -0.06, 0.78), 1.0, eyes=True, jaw_open=0.8)
    # legs: left knee up, right leg out
    hipl, hipr = pel + Vector((-0.09, 0.03, -0.02)), pel + Vector((0.09, 0.03, -0.02))
    kneel, anklel = Vector((-0.13, 0.38, 0.36)), Vector((-0.12, 0.62, 0.05))
    kneer, ankler = Vector((0.13, 0.46, 0.08)), Vector((0.15, 0.86, 0.05))
    for a, kn, an in ((hipl, kneel, anklel), (hipr, kneer, ankler)):
        bone(k, n, a, kn, 0.022)
        bone(k, n, kn, an, 0.017)
        k.box(n, BONE, an + Vector((0, 0.07, -0.02)), (0.06, 0.15, 0.025), 0.004)
    # arms: left wrist on the knee, right hand on the floor
    for sh, el, wr in ((Vector((-0.18, -0.1, 0.58)), Vector((-0.22, 0.08, 0.38)), Vector((-0.14, 0.34, 0.38))),
                       (Vector((0.18, -0.1, 0.58)), Vector((0.25, -0.02, 0.32)), Vector((0.27, 0.16, 0.05)))):
        bone(k, n, sh, el, 0.018)
        bone(k, n, el, wr, 0.014)
        for f in range(4):
            d = Vector(((f - 1.5) * 0.015, 0.06, -0.03))
            k.cyl(n, BONE, wr, wr + d, 0.005, 6, 0.0)


@prop
def bones(k):
    """A pile of skulls and bones."""
    n = "Bones"
    rnd = random.Random(4)
    for i, (x, y) in enumerate(((0, 0), (0.22, 0.12), (-0.2, 0.1), (0.05, 0.26))):
        skull(k, n, (x, y, 0.09 if i else 0.2), 0.9 + 0.1 * rnd.random(), eyes=(i == 0), jaw_open=rnd.random())
    for i in range(10):
        a = rnd.uniform(0, math.tau)
        c = Vector((rnd.uniform(-0.45, 0.45), rnd.uniform(-0.3, 0.45), 0.03))
        d = Vector((math.cos(a), math.sin(a), rnd.uniform(-0.1, 0.25))) * rnd.uniform(0.15, 0.3)
        bone(k, n, c - d, c + d, rnd.uniform(0.013, 0.022))
    k.sphere(n, STONE, (0, 0.1, 0), 0.5, scale=(1.1, 0.9, 0.12), segs=12)  # dirt mound


@prop
def candles(k):
    n = "Candles"
    rnd = random.Random(7)
    for i in range(7):
        a = i * 2.4
        rr = 0.04 + 0.07 * math.sqrt(i)
        p = Vector((math.cos(a) * rr, math.sin(a) * rr, 0))
        h = rnd.uniform(0.1, 0.42) * (1.2 if i == 0 else 1.0)
        r = rnd.uniform(0.022, 0.038)
        k.cyl(n, WAX, p, p + Vector((0, 0, h)), r, 12, 0.002)
        for d in range(3):  # drips
            ang = rnd.uniform(0, math.tau)
            q = p + Vector((math.cos(ang) * r, math.sin(ang) * r, h - rnd.uniform(0.01, 0.06)))
            k.sphere(n, WAX, q, r * 0.35, scale=(1, 1, 2.0), segs=6)
        k.cyl(n, COAL, p + Vector((0, 0, h)), p + Vector((0, 0, h + 0.012)), 0.003, 5, 0)
        flame(k, n, p + Vector((0, 0, h + 0.01)), 0.045)
    k.cyl(n, WAX, (0, 0, 0), (0, 0, 0.01), 0.32, 18, 0.002, r2=0.28)  # melted pool


@prop
def deadTree(k):
    n = "DeadTree"
    rnd = random.Random(21)

    def branch(p, d, length, r, depth):
        segs = 4
        for s in range(segs):
            d = (d + Vector((rnd.uniform(-0.35, 0.35), rnd.uniform(-0.35, 0.35), rnd.uniform(-0.1, 0.25)))).normalized()
            q = p + d * (length / segs)
            r2 = r * (0.86 if s < segs - 1 else 0.7)
            k.cyl(n, BARK, p - d * r * 0.5, q, r, 6, 0.0, r2=r2)  # slight overlap hides the joints
            p, r = q, r2
            if depth < 3 and s >= 1 and rnd.random() < 0.65:
                side = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.1, 0.6))).normalized()
                branch(p, (d * 0.4 + side).normalized(), length * 0.55, r * 0.6, depth + 1)
        if depth < 3:
            for _ in range(2):
                side = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.0, 0.8))).normalized()
                branch(p, side, length * 0.5, r * 0.65, depth + 1)

    branch(Vector((0, 0, 0)), Vector((0.05, 0.02, 1)).normalized(), 2.6, 0.2, 0)
    for i in range(5):  # flared roots
        a = i / 5 * math.tau + 0.3
        k.cyl(n, BARK, (0, 0, 0.25), (math.cos(a) * 0.6, math.sin(a) * 0.6, -0.05), 0.11, 6, 0.0, r2=0.03)


@prop
def tombstone(k):
    n = "Tombstone"
    k.box(n, STONE, (0, 0, 0.32), (0.56, 0.14, 0.64), 0.01, rot=(4, 3, 0))
    k.cyl(n, STONE, (0, -0.07, 0.62), (0, 0.07, 0.66), 0.28, 20, 0.01)   # rounded top
    k.box(n, STONE, (0, 0.02, 0.03), (0.75, 0.3, 0.08), 0.01)
    k.box(n, SOCKET, (0, 0.075, 0.45), (0.32, 0.01, 0.025), 0.001)       # carved lines
    k.box(n, SOCKET, (0, 0.075, 0.38), (0.24, 0.01, 0.02), 0.001)
    k.box(n, SOCKET, (0, 0.075, 0.32), (0.28, 0.01, 0.02), 0.001)


@prop
def tombstoneTall(k):
    n = "TombstoneTall"
    k.box(n, STONE, (0, 0, 0.1), (0.7, 0.7, 0.2), 0.01)
    k.cyl(n, STONE, (0, 0, 0.2), (0, 0, 1.5), 0.24, 4, 0.01, r2=0.17)
    k.cyl(n, STONE, (0, 0, 1.5), (0, 0, 1.85), 0.17, 4, 0.006, r2=0.001)
    skull(k, n, (0, 0.18, 1.05), 0.9, eyes=True, jaw_open=0.2)


@prop
def gothicArch(k):
    """Pointed stone arch over a 2 m gate, skull keystone, raised portcullis teeth."""
    n = "GothicArch"
    for sx in (-1, 1):
        k.box(n, STONE, (sx * 1.3, 0, 1.9), (0.5, 0.55, 3.8), 0.02)
        k.box(n, STONE, (sx * 1.3, 0, 0.12), (0.66, 0.7, 0.24), 0.02)
        k.box(n, STONE, (sx * 1.3, 0, 3.86), (0.62, 0.66, 0.14), 0.02)
        k.cyl(n, IRON, (sx * 1.3, 0, 3.93), (sx * 1.3, 0, 4.7), 0.07, 8, 0.0, r2=0.0)    # pinnacle spike
        # each half of the pointed arch: an arc centred on the opposite pillar face
        cx = -sx * 1.05 * 0.25
        rad = 1.05 + 0.25 * 1.05
        prev = None
        a_max = math.acos(abs(cx) / rad)  # the two arcs meet at x = 0
        for i in range(9):
            a = i / 8 * a_max
            x = cx + sx * rad * math.cos(a)
            z = 3.55 + rad * math.sin(a) * 0.95
            cur = Vector((x, 0, z))
            if prev is not None:
                d = cur - prev
                ang = math.degrees(math.atan2(d.z, d.x))
                k.box(n, STONE, (prev + cur) / 2, (d.length + 0.06, 0.5, 0.3), 0.01, rot=(0, -ang, 0))
            prev = cur
    skull(k, n, (0, 0.22, 4.95), 1.5, eyes=True, jaw_open=0.6)
    for i in range(9):  # raised portcullis teeth
        x = (i - 4) * 0.22
        k.cyl(n, IRON, (x, 0.05, 4.15), (x, 0.05, 3.45), 0.025, 6, 0.0)
        k.cyl(n, IRON, (x, 0.05, 3.45), (x, 0.05, 3.3), 0.025, 6, 0.0, r2=0.0)
    k.box(n, IRON, (0, 0.05, 3.8), (2.1, 0.06, 0.06), 0.004)


@prop
def spikeRow(k):
    """2 m of wrought-iron spear spikes for the fence tops (base at z=0)."""
    n = "SpikeRow"
    k.box(n, IRON, (0, 0, 0.04), (2.0, 0.06, 0.05), 0.004)
    for i in range(9):
        x = (i - 4) * 0.22
        k.cyl(n, IRON, (x, 0, 0.0), (x, 0, 0.42), 0.014, 6, 0.0)
        k.cyl(n, IRON, (x, 0, 0.42), (x, 0, 0.58), 0.04, 4, 0.0, r2=0.0)
        k.sphere(n, IRON, (x, 0, 0.4), 0.03, segs=6)


@prop
def brazier(k):
    n = "Brazier"
    for i in range(3):
        a = i / 3 * math.tau
        k.cyl(n, IRON, (math.cos(a) * 0.38, math.sin(a) * 0.38, 0.0), (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.75), 0.03, 6, 0.002)
        k.sphere(n, IRON, (math.cos(a) * 0.38, math.sin(a) * 0.38, 0.02), 0.045, segs=6)
    k.cyl(n, IRON, (0, 0, 0.7), (0, 0, 0.98), 0.22, 16, 0.003, r2=0.38)
    torus(k, n, IRON, (0, 0, 0.98), 0.38, 0.025)
    for i in range(8):  # rim spikes
        a = i / 8 * math.tau
        k.cyl(n, IRON, (math.cos(a) * 0.38, math.sin(a) * 0.38, 0.98), (math.cos(a) * 0.44, math.sin(a) * 0.44, 1.14), 0.018, 4, 0.0, r2=0.0)
    rnd = random.Random(3)
    for i in range(12):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(0, 0.28)
        k.sphere(n, E_EMBER if i % 3 else COAL, (math.cos(a) * r, math.sin(a) * r, 0.93), rnd.uniform(0.05, 0.09), segs=6)


@prop
def gothicLamp(k):
    """Wrought-iron lamp post with a caged pale-blue flame (replaces LampPost)."""
    n = "GothicLamp"
    k.box(n, STONE, (0, 0, 0.18), (0.45, 0.45, 0.36), 0.02)
    k.cyl(n, IRON, (0, 0, 0.36), (0, 0, 3.7), 0.06, 8, 0.004, r2=0.04)
    for z in (0.5, 1.6, 3.0):
        torus(k, n, IRON, (0, 0, z), 0.07, 0.015)
    torus(k, n, IRON, (0, 0.32, 3.85), 0.3, 0.02, rot=(0, 90, 0))   # curled arm
    k.cyl(n, IRON, (0, 0.62, 3.95), (0, 0.62, 3.75), 0.012, 6, 0.0)
    # lantern cage
    k.cyl(n, IRON, (0, 0.62, 3.75), (0, 0.62, 3.62), 0.13, 6, 0.004, r2=0.17)
    for i in range(6):
        a = i / 6 * math.tau
        k.cyl(n, IRON, (math.cos(a) * 0.15, 0.62 + math.sin(a) * 0.15, 3.62), (math.cos(a) * 0.12, 0.62 + math.sin(a) * 0.12, 3.25), 0.01, 4, 0.0)
    k.cyl(n, IRON, (0, 0.62, 3.25), (0, 0.62, 3.2), 0.13, 6, 0.004)
    flame(k, n, (0, 0.62, 3.27), 0.24, E_BLUE)


@prop
def banner(k):
    """Tattered violet banner on an iron rod, gold trim and a glowing eye."""
    n = "Banner"
    k.cyl(n, IRON, (-0.65, 0.04, 2.5), (0.65, 0.04, 2.5), 0.02, 8, 0.0)
    for sx in (-1, 1):
        k.sphere(n, IRON, (sx * 0.67, 0.04, 2.5), 0.035, segs=6)
    rnd = random.Random(12)
    pts = [(-0.5, 2.48), (0.5, 2.48)]
    z = 0.4
    xs = np.linspace(0.5, -0.5, 9)
    for i, x in enumerate(xs):
        pts.append((float(x), z + (0.25 if i % 2 else 0.0) + rnd.uniform(-0.08, 0.08)))
    slab(k, n, CLOTH, pts, 0.01, y=0.06)
    slab(k, n, GOLD, [(-0.44, 2.42), (0.44, 2.42), (0.44, 2.38), (-0.44, 2.38)], 0.004, y=0.07)
    torus(k, n, GOLD, (0, 0.07, 1.6), 0.22, 0.014, rot=(90, 0, 0))
    k.sphere(n, E_EYE, (0, 0.07, 1.6), 0.12, scale=(1.3, 0.15, 0.55), segs=12)
    k.sphere(n, SOCKET, (0, 0.085, 1.6), 0.045, scale=(0.6, 0.3, 1.0), segs=8)


@prop
def sarcophagus(k):
    """Stone coffin with a cracked-open lid and a skull resting on it (crypt)."""
    n = "Sarcophagus"
    k.box(n, STONE, (0, 0, 0.42), (2.1, 0.9, 0.84), 0.015)
    k.box(n, STONE, (0, 0, 0.06), (2.3, 1.1, 0.12), 0.01)                       # plinth
    k.box(n, STONE, (0.08, 0.05, 0.92), (2.0, 0.84, 0.16), 0.012, rot=(3, 0, 2))  # lid, pushed askew
    for x in (-0.6, 0.0, 0.6):                                                   # carved panels
        k.box(n, SOCKET, (x, -0.46, 0.45), (0.4, 0.01, 0.4), 0.001)
        k.box(n, SOCKET, (x, 0.46, 0.45), (0.4, 0.01, 0.4), 0.001)
    skull(k, n, (-0.55, 0.0, 1.05), 0.8, eyes=True, jaw_open=0.4)
    bone(k, n, (0.3, -0.15, 1.02), (0.85, 0.1, 1.04), 0.035)


@prop
def pew(k):
    """Wooden church bench, worn and tilted (chapel)."""
    n = "Pew"
    k.box(n, BARK, (0, 0.1, 0.45), (1.8, 0.42, 0.06), 0.008)                    # seat
    k.box(n, BARK, (0, -0.17, 0.75), (1.8, 0.05, 0.5), 0.008, rot=(-8, 0, 0))    # backrest
    for sx in (-1, 1):
        k.box(n, BARK, (sx * 0.9, 0.0, 0.42), (0.06, 0.5, 0.84), 0.006)          # side panels
    k.box(n, BARK, (0, 0.32, 0.2), (1.7, 0.05, 0.3), 0.006)                      # kneeler rail
    k.box(n, IRON, (0, 0.1, 0.03), (1.8, 0.3, 0.06), 0.004)                      # iron base


@prop
def obelisk(k):
    """Tapered black stone monument on a plinth with a glowing violet eye slit."""
    n = "Obelisk"
    k.box(n, STONE, (0, 0, 0.2), (1.3, 1.3, 0.4), 0.015)
    k.box(n, STONE, (0, 0, 0.55), (0.9, 0.9, 0.3), 0.012)
    k.cyl(n, STONE, (0, 0, 0.7), (0, 0, 3.4), 0.32, 4, 0.012, r2=0.2)
    k.cyl(n, STONE, (0, 0, 3.4), (0, 0, 3.75), 0.2, 4, 0.008, r2=0.01)
    for z in (1.2, 1.9, 2.6):                                                    # carved bands
        k.box(n, SOCKET, (0, -0.3, z), (0.3, 0.02, 0.05), 0.001)
        k.box(n, SOCKET, (0, 0.3, z), (0.3, 0.02, 0.05), 0.001)
    k.sphere(n, E_EYE, (0, -0.27, 3.0), 0.09, scale=(1.4, 0.3, 0.5), segs=10)


@prop
def gibbet(k):
    """Iron gallows arm with a hanging cage and the remains of its tenant."""
    n = "Gibbet"
    k.box(n, STONE, (0, 0, 0.15), (0.5, 0.5, 0.3), 0.015)
    k.cyl(n, IRON, (0, 0, 0.3), (0, 0, 3.4), 0.07, 8, 0.004)
    k.cyl(n, IRON, (0, 0, 3.4), (0, 1.3, 3.4), 0.05, 8, 0.004)                   # arm
    k.cyl(n, IRON, (0, 0.2, 3.1), (0, 1.0, 3.38), 0.03, 6, 0.002)                # brace
    for i in range(6):                                                           # chain links
        k.cyl(n, IRON, (0, 1.3, 3.35 - i * 0.12), (0, 1.3, 3.25 - i * 0.12), 0.018, 6, 0.0)
    cz = 2.6
    torus(k, n, IRON, (0, 1.3, cz), 0.28, 0.02)                                  # cage rings
    torus(k, n, IRON, (0, 1.3, cz - 0.6), 0.3, 0.02)
    torus(k, n, IRON, (0, 1.3, cz - 1.25), 0.26, 0.02)
    for i in range(8):                                                           # bars
        a = i / 8 * math.tau
        k.cyl(n, IRON, (math.cos(a) * 0.28, 1.3 + math.sin(a) * 0.28, cz), (math.cos(a) * 0.26, 1.3 + math.sin(a) * 0.26, cz - 1.3), 0.012, 4, 0.0)
    skull(k, n, (0, 1.3, cz - 0.25), 0.85, eyes=True, jaw_open=0.5)
    bone(k, n, (-0.1, 1.2, cz - 1.1), (0.12, 1.35, cz - 0.55), 0.03)
    bone(k, n, (0.08, 1.4, cz - 1.15), (-0.08, 1.25, cz - 0.6), 0.028)


# ---------------------------------------------------------------- painting

def paint(P, N_, part, edges, seed):
    N = len(P)
    n1 = pt.fbm(P, 9, 4, seed)
    n2 = pt.fbm(P, 30, 3, seed + 3)
    grime = pt.smooth(0.55, 0.85, pt.fbm(P, 4, 3, seed + 7))
    wear = pt.smooth(0.5, 0.95, edges)
    col = np.zeros((N, 3), np.float32)
    rough = np.full(N, 0.8, np.float32)
    metal = np.zeros(N, np.float32)
    up = np.clip(N_[:, 2], 0, 1)

    bone_c = pt.lerp(pt.hexc("#d2c6a4"), pt.hexc("#9b8d6a"), n1)
    bone_c = pt.lerp(bone_c, pt.hexc("#5a4c38"), pt.smooth(0.6, 0.85, n2) * 0.5)
    stone = pt.lerp(pt.hexc("#71747f"), pt.hexc("#4c4f5a"), n1)
    stone = pt.lerp(stone, pt.hexc("#9a9ca6"), wear * 0.5)
    stone = pt.lerp(stone, pt.hexc("#3d4a37"), pt.smooth(0.5, 0.75, pt.fbm(P, 6, 3, seed + 9)) * up * 0.7)  # moss on top
    cracks = pt.smooth(0.012, 0.0, np.abs(pt.fbm(P, 7, 4, seed + 13) - 0.5))
    stone = pt.lerp(stone, pt.hexc("#22232a"), cracks * 0.8)
    iron = pt.lerp(pt.hexc("#2c2c31"), pt.hexc("#18181b"), n1)
    iron = pt.lerp(iron, pt.hexc("#5b3322"), pt.smooth(0.6, 0.85, pt.fbm(P, 10, 3, seed + 5)) * 0.55)
    iron = pt.lerp(iron, pt.hexc("#6a6a72"), wear * 0.5)
    streak = np.sin(P[:, 0] * 40 + P[:, 1] * 40 + n2 * 8) * 0.5 + 0.5
    bark = pt.lerp(pt.hexc("#3d3531"), pt.hexc("#1f1a18"), np.clip(n1 * 0.6 + streak * 0.4, 0, 1))
    bark = pt.lerp(bark, pt.hexc("#6b665f"), pt.smooth(0.6, 0.8, n2) * 0.4)
    wax = pt.lerp(pt.hexc("#e2d8bf"), pt.hexc("#b8ab8a"), n1)
    cloth = pt.lerp(pt.hexc("#55245f"), pt.hexc("#2c1234"), n1)
    cloth = pt.lerp(cloth, pt.hexc("#170a1c"), grime * 0.6)
    table = {
        BONE: (bone_c, 0.7, 0.0), SOCKET: (np.tile(pt.hexc("#120d10"), (N, 1)), 0.9, 0.0),
        STONE: (stone, 0.88, 0.0), IRON: (iron, 0.55, 0.75), BARK: (bark, 0.9, 0.0),
        WAX: (wax, 0.5, 0.0), CLOTH: (cloth, 0.9, 0.0),
        GOLD: (pt.lerp(pt.hexc("#c39a45"), pt.hexc("#7d5f28"), n1), 0.35, 1.0),
        COAL: (pt.lerp(pt.hexc("#1b1414"), pt.hexc("#3a1a10"), n2), 0.9, 0.0),
    }
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
    ao = lib.bake_ao(ob, TEX, samples=24)
    pos, nor, part, valid = pt.rasterize(ob, TEX)
    rgb = np.zeros((TEX, TEX, 3), np.float32)
    orm = np.zeros((TEX, TEX, 3), np.float32)
    c, r, m = paint(pos[valid], nor[valid], part[valid], edges[valid], 31)
    rgb[valid] = c * (0.35 + 0.65 * ao[valid])[:, None]
    orm[valid] = np.stack([ao[valid], r, m], 1)
    mat = lib.pbr_material("dark_props", pt.to_image(bpy, "dark_props_albedo", rgb, valid),
                           pt.to_image(bpy, "dark_props_orm", orm, valid, non_color=True))
    emissive = {cat: lib.flat_material("emit_" + CATS[cat], hx, emission=hx, strength=st) for cat, (hx, st) in EMISSIVE.items()}
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
        off = Vector(((i % 4) * 6.0, (i // 4) * 6.0, 0))
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
    if len(ob.data.vertices):
        print("  (dropping %d ungrouped vertices)" % len(ob.data.vertices))
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
        layout = {"SkeletonSit": (0, 0), "Bones": (1.5, 0), "Candles": (3, 0), "Tombstone": (4.5, 0),
                  "TombstoneTall": (6, 0), "Brazier": (7.5, 0), "Banner": (9, 0.5),
                  "DeadTree": (1, -5), "GothicArch": (5, -5), "GothicLamp": (8.5, -4), "SpikeRow": (11, -2),
                  "Sarcophagus": (0, -10), "Pew": (3, -10), "Obelisk": (6, -10), "Gibbet": (9, -10)}
        for name, o in nodes.items():
            x, y = layout.get(name, (12, 0))
            o.location = (x, y, 0)
        lib.render_setup((1600, 900), samples=32)
        bpy.context.scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.1, 1)
        bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 2.0
        lib.add_camera((5.5, 9.0, 4.5), (5.5, -2.0, 1.4), lens=26)
        lib.add_light('SUN', (0, 0, 10), 3.0, (0.85, 0.85, 1.0), rot=(math.radians(50), 0, math.radians(160)))
        bpy.ops.mesh.primitive_plane_add(size=60, location=(5, -3, 0))
        lib.render(os.path.join(d, "dark_props.png"))


if __name__ == "__main__":
    main()
