"""Builds Blackoff's two zombie archetypes as rigged, animated GLB files.

  walker -> facility security guard (peaked cap, navy uniform, belt, torn shirt)
  runner -> lab scientist (blood-soaked lab coat, shirt and tie, slacks)

Run:  /opt/blender-venv/bin/python art/blender/build_zombies.py [--preview DIR]
Output: client/assets/models/zombie_<variant>.glb
Animations (shared skeleton): idle, walk, run, attack, hit, death.
Everything is generated here: geometry (skin modifier anatomy), rig (auto
weights), keyframed animation, and textures painted by painter.py.
"""
import math
import os
import random
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
import painter as pt  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "client", "assets", "models")
TEX = 1024

# Part ids (polygon material index) used by the painter.
BODY, HEAD, CAP, BELT, COAT, EYES = range(6)

# ---------------------------------------------------------------- anatomy (faces +Y, Z up)
def joints(variant):
    boots = variant == "walker"
    j = {
        "pelvis": ((0, 0.0, 1.00), (0.168, 0.118)),
        "waist": ((0, 0.01, 1.12), (0.158, 0.11)),
        "chest": ((0, 0.02, 1.29), (0.192, 0.13)),
        "upchest": ((0, 0.006, 1.40), (0.205, 0.12)),
        "neck": ((0, 0.012, 1.505), (0.056, 0.06)),
        "neck_top": ((0, 0.02, 1.565), (0.06, 0.066)),
        "clav.L": ((0.1, 0.0, 1.45), (0.072, 0.066)),
        "shoulder.L": ((0.205, -0.002, 1.425), (0.078, 0.074)),
        "bicep.L": ((0.272, -0.006, 1.33), (0.064, 0.064)),
        "elbow.L": ((0.352, -0.012, 1.215), (0.045, 0.046)),
        "fore.L": ((0.425, -0.006, 1.13), (0.049, 0.043)),
        "wrist.L": ((0.5, 0.0, 1.045), (0.034, 0.028)),
        "palm.L": ((0.545, 0.008, 0.99), (0.046, 0.022)),
        "hip.L": ((0.094, 0.0, 0.95), (0.105, 0.108)),
        "thigh_mid.L": ((0.099, 0.012, 0.75), (0.09, 0.092)),
        "knee.L": ((0.1, 0.02, 0.525), (0.058, 0.062)),
        "calf.L": ((0.1, -0.006, 0.36), (0.066, 0.07)),
        "shin_low.L": ((0.1, -0.008, 0.2), (0.058, 0.062)),
        "ankle.L": ((0.1, -0.008, 0.1), (0.05 if boots else 0.043, 0.054 if boots else 0.046)),
        "heel.L": ((0.1, -0.055, 0.04), (0.046 if boots else 0.04, 0.036)),
        "toe.L": ((0.1, 0.15, 0.04), (0.05 if boots else 0.044, 0.038 if boots else 0.03)),
    }
    # claw-like fingers fanned along the palm edge (A-pose arm points down/out)
    for i, fy in enumerate((-0.018, -0.004, 0.01, 0.024)):
        j["fing%d_a.L" % i] = ((0.575, 0.008 + fy, 0.955), (0.012, 0.011))
        j["fing%d_b.L" % i] = ((0.6, 0.016 + fy * 1.1, 0.92), (0.0105, 0.0095))
        j["fing%d_c.L" % i] = ((0.606, 0.03 + fy * 1.15, 0.893), (0.008, 0.007))
    j["thumb_a.L"] = ((0.538, 0.035, 0.985), (0.014, 0.013))
    j["thumb_b.L"] = ((0.556, 0.058, 0.958), (0.011, 0.01))
    return j


EDGES = [
    ("pelvis", "waist"), ("waist", "chest"), ("chest", "upchest"), ("upchest", "neck"), ("neck", "neck_top"),
    ("upchest", "clav.L"), ("clav.L", "shoulder.L"), ("shoulder.L", "bicep.L"), ("bicep.L", "elbow.L"),
    ("elbow.L", "fore.L"), ("fore.L", "wrist.L"), ("wrist.L", "palm.L"),
    ("palm.L", "thumb_a.L"), ("thumb_a.L", "thumb_b.L"),
    ("pelvis", "hip.L"), ("hip.L", "thigh_mid.L"), ("thigh_mid.L", "knee.L"), ("knee.L", "calf.L"),
    ("calf.L", "shin_low.L"), ("shin_low.L", "ankle.L"), ("ankle.L", "heel.L"), ("ankle.L", "toe.L"),
] + [e for i in range(4) for e in (("palm.L", "fing%d_a.L" % i), ("fing%d_a.L" % i, "fing%d_b.L" % i),
                                   ("fing%d_b.L" % i, "fing%d_c.L" % i))]

HEAD_C = Vector((0, 0.022, 1.665))
HEAD_R = Vector((0.092, 0.106, 0.123))
EYE_L = Vector((0.034, 0.088, 0.006))   # relative to HEAD_C

BONES = [  # name, head, tail, parent
    ("hips", (0, 0, 1.0), (0, 0.008, 1.12), None),
    ("spine", (0, 0.008, 1.12), (0, 0.018, 1.29), "hips"),
    ("chest", (0, 0.018, 1.29), (0, 0.01, 1.47), "spine"),
    ("neck", (0, 0.01, 1.47), (0, 0.02, 1.565), "chest"),
    ("head", (0, 0.02, 1.565), (0, 0.025, 1.80), "neck"),
    ("clavicle.L", (0.03, 0.0, 1.44), (0.2, -0.002, 1.425), "chest"),
    ("upper_arm.L", (0.2, -0.002, 1.425), (0.352, -0.012, 1.215), "clavicle.L"),
    ("forearm.L", (0.352, -0.012, 1.215), (0.5, 0.0, 1.045), "upper_arm.L"),
    ("hand.L", (0.5, 0.0, 1.045), (0.6, 0.02, 0.9), "forearm.L"),
    ("thigh.L", (0.092, 0.0, 0.95), (0.1, 0.02, 0.525), "hips"),
    ("shin.L", (0.1, 0.02, 0.525), (0.1, -0.008, 0.1), "thigh.L"),
    ("foot.L", (0.1, -0.008, 0.1), (0.1, 0.15, 0.04), "shin.L"),
]


def _mirror_name(n):
    return n[:-2] + ".R" if n.endswith(".L") else n


def build_body(variant):
    j = joints(variant)
    for name, (p, r) in list(j.items()):
        if name.endswith(".L"):
            j[_mirror_name(name)] = ((-p[0], p[1], p[2]), r)
    edges = list(EDGES) + [(_mirror_name(a), _mirror_name(b)) for a, b in EDGES if a.endswith(".L") or b.endswith(".L")]
    names = list(j.keys())
    me = bpy.data.meshes.new("body")
    me.from_pydata([j[n][0] for n in names], [(names.index(a), names.index(b)) for a, b in edges], [])
    ob = lib.link(bpy.data.objects.new("body", me))
    skin = ob.modifiers.new("skin", 'SKIN')
    skin.branch_smoothing = 0.55
    skin.use_smooth_shade = True
    for i, n in enumerate(names):
        sv = me.skin_vertices[0].data[i]
        sv.radius = j[n][1]
        sv.use_root = n == "pelvis"
    ob.modifiers.new("sub", 'SUBSURF').levels = 1
    lib.apply_modifiers(ob)
    return ob


def build_head(mouth_open):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=30, ring_count=22, radius=1.0)
    ob = bpy.context.active_object
    ob.name = "head"
    for v in ob.data.vertices:
        x, y, z = v.co
        p = Vector((x * HEAD_R.x, y * HEAD_R.y, z * HEAD_R.z))
        front = max(0.0, y)
        if z < -0.2:                                   # jaw: narrower, forward, hanging
            k = min(1.0, (-0.2 - z) / 0.8)
            p.x *= 1.0 - 0.2 * k
            p.y += 0.014 * k * front
            p.z -= 0.024 * k * mouth_open
        if z > 0.35:                                   # cranium slightly longer at the back
            p.y -= 0.01 * (z - 0.35) * (1 - front)
        if 0.06 < z < 0.34 and y > 0.5:                # heavy brow
            p.y += 0.012 * max(0.0, 1 - abs(z - 0.2) / 0.14)
        for sx in (-0.37, 0.37):                       # deep eye sockets
            d = math.hypot(x - sx, (z - 0.03) * 1.3)
            if y > 0.55 and d < 0.24:
                p.y -= 0.02 * (1 - d / 0.24)
        dn = math.hypot(x * 1.7, z + 0.13)              # nose
        if y > 0.7 and dn < 0.2:
            p.y += 0.024 * (1 - dn / 0.2)
        dm = math.hypot(x * 1.05, (z + 0.47) * 1.5)     # gaping mouth
        if y > 0.55 and dm < 0.32:
            p.y -= 0.034 * (1 - dm / 0.32) * mouth_open
        if y > 0.25 and -0.48 < z < -0.12 and abs(x) > 0.42:  # sunken cheeks
            p.x *= 0.94
        for sx in (-1, 1):                             # ears
            de = math.hypot(y + 0.05, z + 0.02)
            if x * sx > 0.9 and de < 0.25:
                p.x += sx * 0.012 * (1 - de / 0.25)
        v.co = p + HEAD_C
    ob.modifiers.new("sub", 'SUBSURF').levels = 1
    lib.apply_modifiers(ob)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    return ob


def build_eyes():
    out = []
    for sx in (1, -1):
        loc = HEAD_C + Vector((EYE_L.x * sx, EYE_L.y, EYE_L.z))
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.0112, location=loc)
        out.append(bpy.context.active_object)
    return lib.join(out, "eyes")


def ring(name, z, rx, ry, height, segments=24, thickness=0.012):
    bm = bmesh.new()
    rows = [[bm.verts.new((math.cos(2 * math.pi * i / segments) * rx, math.sin(2 * math.pi * i / segments) * ry, zz))
             for i in range(segments)] for zz in (z - height / 2, z + height / 2)]
    for i in range(segments):
        k = (i + 1) % segments
        bm.faces.new((rows[0][i], rows[0][k], rows[1][k], rows[1][i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = lib.link(bpy.data.objects.new(name, me))
    ob.modifiers.new("sol", 'SOLIDIFY').thickness = thickness
    lib.apply_modifiers(ob)
    return ob


def guard_cap():
    c = HEAD_C
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.102, depth=0.075, location=(0, c.y - 0.006, c.z + 0.088))
    crown = bpy.context.active_object
    crown.scale = (1.0, 1.1, 1.0)
    crown.rotation_euler = (math.radians(-9), 0, 0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.112, depth=0.02, location=(0, c.y - 0.012, c.z + 0.128))
    top = bpy.context.active_object
    top.scale = (1.0, 1.12, 1.0)
    top.rotation_euler = (math.radians(-12), 0, 0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.075, depth=0.01, location=(0, c.y + 0.09, c.z + 0.06))
    brim = bpy.context.active_object
    brim.scale = (1.15, 0.8, 1.0)
    brim.rotation_euler = (math.radians(16), 0, 0)
    for o in (crown, top, brim):
        lib.activate(o)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    cap = lib.join([crown, top, brim], "cap")
    for p in cap.data.polygons:
        p.use_smooth = True
    return cap


def coat_skirt():
    """Lab coat below the waist: flared, open at the front, tattered hem."""
    rng = random.Random(4)
    bm = bmesh.new()
    levels = [(1.1, 0.172, 0.124), (0.98, 0.186, 0.134), (0.84, 0.205, 0.148), (0.7, 0.225, 0.165), (0.55, 0.24, 0.18)]
    seg = 28
    front = seg // 4
    rows = []
    for li, (z, rx, ry) in enumerate(levels):
        row = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            zz = z + (rng.uniform(-0.07, 0.04) if li == len(levels) - 1 else 0.0)
            row.append(bm.verts.new((math.cos(a) * rx, math.sin(a) * ry + 0.01, zz)))
        rows.append(row)
    for li in range(len(levels) - 1):
        for i in range(seg):
            if front - 2 <= i <= front + 1 and li >= 1:
                continue  # open front, closed at the waist
            k = (i + 1) % seg
            bm.faces.new((rows[li][i], rows[li][k], rows[li + 1][k], rows[li + 1][i]))
    me = bpy.data.meshes.new("coat")
    bm.to_mesh(me)
    bm.free()
    ob = lib.link(bpy.data.objects.new("coat", me))
    ob.modifiers.new("sol", 'SOLIDIFY').thickness = 0.008
    ob.modifiers.new("sub", 'SUBSURF').levels = 1
    lib.apply_modifiers(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


# ---------------------------------------------------------------- texture painting

def paint(variant, P, part, rng_seed):
    """Returns RGB (N,3) for texels at rest positions P with part ids."""
    N = len(P)
    out = np.zeros((N, 3), np.float32)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    n_lo = pt.fbm(P, 4, 4, rng_seed)
    n_mid = pt.fbm(P, 11, 4, rng_seed + 50)
    n_hi = pt.vnoise(P, 160, rng_seed + 90)
    edge = (pt.fbm(P, 22, 3, rng_seed + 7) - 0.5)  # ragged edges for tears

    # --- skin
    pale = variant == "runner"
    base_a, base_b = (pt.hexc("#8d877d"), pt.hexc("#5f6156")) if pale else (pt.hexc("#727a66"), pt.hexc("#4b5343"))
    skin = pt.lerp(base_a, base_b, n_lo)
    rot = pt.smooth(0.58, 0.78, pt.fbm(P, 6, 3, rng_seed + 3))
    skin = pt.lerp(skin, pt.hexc("#5c5838"), rot * 0.55)
    bruise = pt.smooth(0.62, 0.8, pt.fbm(P, 7, 3, rng_seed + 9))
    skin = pt.lerp(skin, pt.hexc("#5b4b63"), bruise * 0.5)
    veins = pt.smooth(0.028, 0.0, np.abs(pt.fbm(P, 16, 3, rng_seed + 5) - 0.5))
    skin = pt.lerp(skin, pt.hexc("#433d52"), veins * 0.55)
    skin *= (0.9 + 0.1 * n_hi)[:, None]

    rel = P - np.array(HEAD_C, np.float32)
    head_skin = skin.copy()
    for sx in (-1, 1):  # eye sockets, dark and bruised
        d = np.hypot((rel[:, 0] - sx * EYE_L.x) * 1.0, (rel[:, 2] - EYE_L.z) * 1.25)
        head_skin = pt.lerp(head_skin, pt.hexc("#3c2a35"), pt.smooth(0.05, 0.03, d) * 0.7 * pt.smooth(0.0, 0.05, rel[:, 1]))
        head_skin = pt.lerp(head_skin, pt.hexc("#120807"), pt.smooth(0.026, 0.014, d) * pt.smooth(0.02, 0.06, rel[:, 1]))
    front = rel[:, 1] > 0.04
    fw = pt.smooth(0.0, 0.06, rel[:, 1])          # soft "faces forward" weight
    # painted form shading (all soft): brow shadow, cheek hollows, darker back of head
    brow = fw * pt.smooth(0.03, 0.0, np.abs(rel[:, 2] - 0.03)) * pt.smooth(0.09, 0.05, np.abs(rel[:, 0]))
    head_skin = head_skin * (1 - 0.25 * brow)[:, None]
    hollow = pt.smooth(0.035, 0.0, np.hypot(np.abs(rel[:, 0]) - 0.055, rel[:, 2] + 0.04)) * fw
    head_skin = head_skin * (1 - 0.35 * hollow)[:, None]
    head_skin = head_skin * (1 - 0.12 * pt.smooth(0.0, -0.06, rel[:, 1]))[:, None]
    dm = np.hypot(rel[:, 0] * 1.15, (rel[:, 2] + 0.062) * 1.9)
    front = rel[:, 1] > 0.04
    head_skin = pt.lerp(head_skin, pt.hexc("#4a0a07"), pt.smooth(0.075, 0.035, dm) * fw)
    head_skin = np.where((front & (dm < 0.03))[:, None], pt.hexc("#0d0404"), head_skin)
    teeth = front & (dm < 0.034) & (dm > 0.02) & (rel[:, 2] > -0.058) & (np.sin(rel[:, 0] * 420) > -0.2)
    head_skin = np.where(teeth[:, None], pt.lerp(pt.hexc("#b8ab8a"), pt.hexc("#6d5a3c"), n_mid), head_skin)
    # blood drips from the mouth down the chin
    if pale:  # patchy hair
        hairline = 0.05 - 0.07 * pt.smooth(0.03, -0.05, rel[:, 1]) + 0.02 * edge
        hair = (rel[:, 2] > hairline) & (pt.fbm(P, 30, 3, rng_seed + 13) > 0.42)
        head_skin = np.where(hair[:, None], pt.lerp(pt.hexc("#2b2520"), pt.hexc("#151210"), n_mid), head_skin)

    # --- blood layer helpers
    def blood(color, amount, seed, scale=9.0):
        b = pt.fbm(P, scale, 5, seed)
        mask = pt.smooth(1 - amount * 0.55, 1 - amount * 0.55 + 0.03, b)
        fresh = pt.lerp(pt.hexc("#3e0605"), pt.hexc("#1e0302"), pt.vnoise(P, 25, seed + 1))
        dried = pt.lerp(color, pt.hexc("#2f1a12"), 0.45)
        stain = pt.smooth(1 - amount, 1 - amount + 0.12, b)  # soaked halo around splats
        return pt.lerp(pt.lerp(color, dried, stain * 0.5), fresh, mask * 0.95)

    def drips(region, top_z, seed, density=0.5, max_len=0.25):
        """Organic drips: wavy, tapering columns running down from top_z."""
        wob = (pt.vnoise(P * np.array([0, 0, 1], np.float32), 25, seed) - 0.5) * 0.012
        xs = np.stack([(x + wob) * 1.0, np.zeros(N), np.zeros(N)], 1).astype(np.float32)
        col = pt.vnoise(xs, 70, seed + 1)
        length = max_len * pt.vnoise(xs, 33, seed + 2)
        depth = top_z - z
        taper = 1 - depth / np.maximum(length, 1e-3)
        m = region & (depth > 0) & (depth < length) & (col > 1 - density * taper.clip(0, 1) * 0.6)
        return m

    head_drip = drips(front & (ax < 0.03 + 0.02 * edge), HEAD_C.z - 0.07, rng_seed + 11, 0.35, 0.1)
    head_skin = np.where(head_drip[:, None], pt.hexc("#330504"), head_skin)

    def fabric(c1, c2, scale=8.0, seed=0):
        c = pt.lerp(pt.hexc(c1), pt.hexc(c2), pt.fbm(P, scale, 4, rng_seed + seed))
        weave = 0.97 + 0.03 * np.sin(P[:, 0] * 900) * np.sin(P[:, 2] * 900)
        return c * weave[:, None]

    body = skin.copy()
    arm = ax > 0.215
    if variant == "walker":
        shirt = fabric("#33404f", "#1d2530", 7, 1)
        shirt = np.where((z > 1.465)[:, None] & ~arm[:, None], shirt * 0.75, shirt)          # collar
        btn = (ax < 0.006) & (y > 0.09) & (np.mod(z, 0.075) < 0.012) & (z > 1.0) & (z < 1.46)
        shirt = np.where(btn[:, None], pt.hexc("#0d1116"), shirt)                             # buttons
        pocket = (y > 0.08) & (ax > 0.05) & (ax < 0.13) & (z > 1.3) & (z < 1.385)
        pocket_edge = pocket & ((np.abs(ax - 0.05) < 0.004) | (np.abs(ax - 0.13) < 0.004) | (np.abs(z - 1.385) < 0.004))
        shirt = np.where(pocket_edge[:, None], shirt * 0.6, shirt)
        badge = (y > 0.08) & (x > 0.07) & (x < 0.11) & (z > 1.395) & (z < 1.43)
        shirt = np.where(badge[:, None], pt.lerp(pt.hexc("#c8a64a"), pt.hexc("#7a6020"), n_hi), shirt)
        patch = (x > 0.22) & (z > 1.33) & (z < 1.41) & (y < 0.02)
        shirt = np.where(patch[:, None], pt.hexc("#6a5420"), shirt)                           # shoulder patch
        shirt = blood(shirt, 0.3, rng_seed + 20)
        soak = pt.smooth(1.25, 1.48, z) * (y > 0.04) * pt.smooth(0.12, 0.02, ax) * pt.fbm(P, 8, 3, 61)
        shirt = pt.lerp(shirt, pt.hexc("#2a0504"), np.clip(soak * 1.6, 0, 0.9))           # blood soaked from the mouth
        shirt = np.where(drips((y > 0.05) & (ax < 0.12), 1.3, 77, 0.6, 0.3)[:, None], pt.hexc("#2c0403"), shirt)
        pants = fabric("#2a2e34", "#15171a", 6, 2)
        knees = pt.smooth(0.07, 0.0, np.abs(z - 0.53)) * (y > 0.01)
        pants = pt.lerp(pants, pt.hexc("#454a50"), knees * 0.6)
        mud = pt.smooth(0.42, 0.12, z) * pt.fbm(P, 9, 3, 33)
        pants = pt.lerp(pants, pt.hexc("#3d3226"), mud)
        boots = pt.lerp(pt.hexc("#1a1612"), pt.hexc("#0a0807"), n_mid)
        laces = (y > 0.03) & (z > 0.07) & (z < 0.17) & (np.sin(z * 260) > 0.6) & (ax > 0.08) & (ax < 0.12)
        boots = np.where(laces[:, None], pt.hexc("#3a342c"), boots)
        is_boot = z < 0.165 + edge * 0.01
        is_pants = (z < 0.985 + edge * 0.004) & ~arm
        sleeve = arm & np.where(x > 0, z > 1.29 + edge * 0.06, z > 1.075 + edge * 0.01)       # left sleeve ripped
        torso = (~arm) & (z >= 0.985) & (z < 1.507 + edge * 0.004)
        tear = (y > 0.03) & (x > 0.02) & (x < 0.16) & (z > 1.1) & (z < 1.31) & (edge + 0.5 > 0.42)
        body = np.where(is_boot[:, None], boots, np.where(is_pants[:, None], pants, body))
        body = np.where((torso | sleeve)[:, None], shirt, body)
        flesh = pt.lerp(pt.hexc("#4a0c09"), pt.hexc("#1c0302"), pt.fbm(P, 30, 3, 4))
        rim = pt.lerp(skin, pt.hexc("#3a0806"), 0.6)
        tear_core = tear & (edge + 0.5 > 0.5)
        body = np.where(tear[:, None], rim, body)
        body = np.where(tear_core[:, None], flesh, body)
        thigh_hole = (x < -0.05) & (y > 0.04) & (z > 0.68) & (z < 0.8) & (edge + 0.5 > 0.48)
        body = np.where(thigh_hole[:, None], pt.lerp(skin, pt.hexc("#4a0806"), 0.5), body)
    else:
        coat = fabric("#d2d4d2", "#8e9290", 5, 4)
        coat = pt.lerp(coat, pt.hexc("#6f6a55"), pt.smooth(0.55, 0.85, pt.fbm(P, 3, 3, 40)) * 0.6)  # grime
        coat = blood(coat, 0.45, rng_seed + 30, 6)
        coat = np.where(drips((y > 0.05) & (ax < 0.16), 1.38, 79, 0.6, 0.35)[:, None], pt.hexc("#2c0403"), coat)
        shirt = fabric("#8fa5bb", "#5c6f82", 8, 5)
        tie = pt.lerp(pt.hexc("#5c1b1d"), pt.hexc("#2c0b0c"), n_mid)
        pants = fabric("#4d5054", "#2b2d30", 6, 6)
        shoes = pt.lerp(pt.hexc("#2d2017"), pt.hexc("#120c08"), n_mid)
        v_open = (y > 0.0) & (ax < 0.03 + np.maximum(0, 1.46 - z) * 0.28) & (z > 1.02)
        tie_m = (y > 0.0) & (ax < 0.012 + np.maximum(0, 1.46 - z) * 0.035) & (z > 1.1) & (z < 1.47)
        lapel = (y > 0.0) & (np.abs(ax - (0.03 + np.maximum(0, 1.46 - z) * 0.28)) < 0.008) & (z > 1.02)
        badge = (y > 0.08) & (x > 0.12) & (x < 0.165) & (z > 1.32) & (z < 1.36)
        is_shoe = z < 0.12 + edge * 0.01
        is_pants = (z < 0.985) & ~arm
        sleeve = arm & (z > 1.065 + edge * 0.012)
        torso = (~arm) & (z >= 0.985) & (z < 1.507)
        upper = np.where(v_open[:, None], np.where(tie_m[:, None], tie, shirt), coat)
        upper = np.where(lapel[:, None], coat * 0.7, upper)
        upper = np.where(badge[:, None], np.where((z > 1.345)[:, None], pt.hexc("#2a5b8c"), pt.hexc("#e8e6e0")), upper)
        body = np.where(is_shoe[:, None], shoes, np.where(is_pants[:, None], pants, body))
        body = np.where(torso[:, None], upper, body)
        body = np.where(sleeve[:, None], coat, body)
        neck_bite = (x < -0.02) & (z > 1.47) & (z < 1.56) & (edge + 0.5 > 0.5)
        body = np.where(neck_bite[:, None], pt.hexc("#4a0806"), body)

    out[:] = body
    out = np.where((part == HEAD)[:, None], head_skin, out)
    cap = pt.lerp(pt.hexc("#222b39"), pt.hexc("#0e131b"), n_mid)
    cap = np.where(((rel[:, 2] < 0.075) & (rel[:, 2] > 0.05))[:, None], cap * 0.6, cap)          # band
    emblem = (np.hypot(rel[:, 0], rel[:, 2] - 0.1) < 0.018) & (rel[:, 1] > 0.08)
    cap = np.where(emblem[:, None], pt.hexc("#b49a4a"), cap)
    out = np.where((part == CAP)[:, None], cap, out)
    belt = np.where(((ax < 0.022) & (y > 0.05))[:, None], pt.hexc("#8d9094"), pt.lerp(pt.hexc("#151311"), pt.hexc("#050404"), n_hi)[...])
    out = np.where((part == BELT)[:, None], belt, out)
    if variant == "runner":
        skirt = fabric("#cfd1cf", "#8a8e8c", 5, 4)
        hem = pt.smooth(0.66, 0.55, z)
        skirt = pt.lerp(skirt, pt.hexc("#5c5646"), hem * 0.7)
        pocket = (np.abs(ax - 0.13) < 0.05) & (z > 0.8) & (z < 0.9) & (y > 0.03)
        skirt = np.where((pocket & ((np.abs(z - 0.9) < 0.005) | (np.abs(np.abs(ax - 0.13) - 0.05) < 0.005)))[:, None], skirt * 0.65, skirt)
        skirt = blood(skirt, 0.35, rng_seed + 31, 6)
        out = np.where((part == COAT)[:, None], skirt, out)
    return np.clip(out, 0, 1)


def texture(ob, variant, seed):
    """UV-unwrap, paint, bake AO, and replace materials (eyes stay emissive)."""
    # Give the head (seen up close) ~3x texel density: inflate it during unwrap.
    head_v = set()
    for p in ob.data.polygons:
        if p.material_index in (HEAD, CAP):
            head_v.update(p.vertices)
    saved = {i: ob.data.vertices[i].co.copy() for i in head_v}
    for i in head_v:
        ob.data.vertices[i].co = HEAD_C + (saved[i] - HEAD_C) * 1.8
    lib.activate(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=0.005)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.004, shape_method='CONCAVE')
    bpy.ops.object.mode_set(mode='OBJECT')
    for i, co in saved.items():
        ob.data.vertices[i].co = co
    pos, nor, part, valid = pt.rasterize(ob, TEX)
    rgb = np.zeros((TEX, TEX, 3), np.float32)
    rgb[valid] = paint(variant, pos[valid], part[valid], seed)
    # ambient occlusion from Cycles, multiplied in
    ao_img = bpy.data.images.new("ao", TEX, TEX)
    for slot in ob.material_slots:
        nt = slot.material.node_tree
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = ao_img
        nt.nodes.active = node
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 32
    sc.render.bake.margin = 4
    lib.activate(ob)
    bpy.ops.object.bake(type='AO')
    ao = np.array(ao_img.pixels[:], np.float32).reshape(TEX, TEX, 4)[..., 0]
    rgb *= (0.42 + 0.58 * ao)[..., None]
    img = pt.to_image(bpy, "zombie_%s_albedo" % variant, rgb, valid)
    mat = bpy.data.materials.new("zombie_" + variant)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.78
    eyes = lib.flat_material("eyes", "#ffb347" if variant == "walker" else "#ff6a3a",
                             emission="#ff9a2a" if variant == "walker" else "#ff3a1a", strength=8.0)
    # Reassign slots in place (clearing the list would reset face indices);
    # the glTF exporter merges slots sharing a material into one primitive.
    for i in range(len(ob.data.materials)):
        ob.data.materials[i] = eyes if i == EYES else mat


def part_mat(name):
    return lib.flat_material(name, "#808080")


def build_variant(variant):
    lib.reset()
    parts = []
    body = build_body(variant)
    head = build_head(mouth_open=0.75 if variant == "walker" else 1.0)
    eyes = build_eyes()
    parts += [(body, BODY), (head, HEAD), (eyes, EYES)]
    if variant == "walker":
        parts.append((guard_cap(), CAP))
        parts.append((ring("belt", 0.99, 0.166, 0.116, 0.045), BELT))
    else:
        parts.append((coat_skirt(), COAT))
    mats = [part_mat(n) for n in ("body", "head", "cap", "belt", "coat", "eyes")]
    for ob, idx in parts:
        if idx in (CAP, BELT, COAT, EYES):
            vg = ob.vertex_groups.new(name="part_%d" % idx)
            vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
        ob.data.materials.clear()
        for m in mats:
            ob.data.materials.append(m)
        for p in ob.data.polygons:
            p.material_index = idx
            p.use_smooth = True
    return lib.join([o for o, _ in parts], "zombie_" + variant)


# ---------------------------------------------------------------- rig

def build_armature(mesh_ob, scale=1.0):
    arm = bpy.data.armatures.new("rig")
    ao = lib.link(bpy.data.objects.new("rig", arm))
    lib.activate(ao)
    bpy.ops.object.mode_set(mode='EDIT')
    all_bones = []
    for name, h, t, parent in BONES:
        all_bones.append((name, h, t, parent))
        if name.endswith(".L"):
            all_bones.append((_mirror_name(name), (-h[0], h[1], h[2]), (-t[0], t[1], t[2]),
                              _mirror_name(parent) if parent else None))
    eb = {}
    for name, h, t, parent in all_bones:
        b = arm.edit_bones.new(name)
        b.head = Vector(h) * scale
        b.tail = Vector(t) * scale
        b.roll = 0.0
        eb[name] = b
    for name, h, t, parent in all_bones:
        if parent:
            eb[name].parent = eb[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    lib.activate(ao, mesh_ob)
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    fix_part_weights(mesh_ob)
    return ao


def fix_part_weights(ob):
    """Rigid parts get explicit weights (auto weights let hands grab the coat)."""
    groups = {g.name: g for g in ob.vertex_groups}
    deform = [g for g in ob.vertex_groups if not g.name.startswith("part_")]
    for part, rule in ((CAP, "head"), (EYES, "head"), (BELT, "belt"), (COAT, "coat")):
        pg = groups.get("part_%d" % part)
        if pg is None:
            continue
        idx = [v.index for v in ob.data.vertices if any(g.group == pg.index for g in v.groups)]
        for g in deform:
            g.remove(idx)
        for i in idx:
            co = ob.data.vertices[i].co
            if rule == "head":
                groups["head"].add([i], 1.0, 'REPLACE')
            elif rule == "belt":
                groups["hips"].add([i], 1.0, 'REPLACE')
            else:
                # coat skirt: hips at the waist blending into the thigh on its side
                t = min(1.0, max(0.0, (1.02 - co.z) / 0.42))
                side = "thigh.L" if co.x > 0 else "thigh.R"
                w_side = t * min(1.0, abs(co.x) / 0.08)
                groups["hips"].add([i], 1.0 - w_side * 0.85, 'REPLACE')
                groups[side].add([i], w_side * 0.85, 'REPLACE')
    for g in list(ob.vertex_groups):
        if g.name.startswith("part_"):
            ob.vertex_groups.remove(g)


# ---------------------------------------------------------------- animation

def aim(x, y, z):
    return {"aim": (x, y, z)}


def arms(lu, lf, lh, ru, rf, rh):
    """Left upper/fore/hand aims and right ones (given in right-side coords, x<0)."""
    return {"upper_arm.L": aim(*lu), "forearm.L": aim(*lf), "hand.L": aim(*lh),
            "upper_arm.R": aim(*ru), "forearm.R": aim(*rf), "hand.R": aim(*rh)}


REACH = arms((0.24, 0.92, -0.16), (0.12, 0.97, -0.02), (0.06, 0.8, -0.55),
             (-0.3, 0.85, -0.38), (-0.16, 0.9, -0.3), (-0.1, 0.6, -0.8))
HANG = arms((0.3, 0.5, -0.8), (0.2, 0.7, -0.6), (0.1, 0.4, -0.9),
            (-0.32, 0.45, -0.82), (-0.2, 0.6, -0.75), (-0.1, 0.4, -0.9))
SHAMBLE = {"spine": (-14, 0, 3), "chest": (-10, 0, -5), "neck": (6, 0, 0), "head": (10, 8, 16)}


LEG_T, LEG_S = 0.428, 0.427


LEG_SCALE = [1.0]


def plant(lg, extra=0.0):
    """Hips Z offset that keeps the lower foot on the floor for these leg angles."""
    reach = []
    for side in ("L", "R"):
        t = math.radians(lg["thigh." + side][0])
        s_ = math.radians(lg["shin." + side][0])
        reach.append(LEG_T * math.cos(t) + LEG_S * math.cos(t + s_))
    return (0, 0, (max(reach) - (LEG_T + LEG_S)) * LEG_SCALE[0] + extra)


def legs(lt, ls, rt, rs, lf=0, rf=0):
    return {"thigh.L": (lt, 0, 0), "shin.L": (ls, 0, 0), "foot.L": (lf, 0, 0),
            "thigh.R": (rt, 0, 0), "shin.R": (rs, 0, 0), "foot.R": (rf, 0, 0)}


def sway_arms(base, dz):
    return {k: aim(v["aim"][0], v["aim"][1], v["aim"][2] + dz) for k, v in base.items()}


def build_actions(ao):
    acts = []
    stance = legs(10, -12, -8, -12)
    st_off = plant(stance)
    acts.append(lib.new_action(ao, "idle"))
    for f, s in ((0, -1), (24, 1), (48, -1)):
        lib.key_pose(ao, f, lib.merge(sway_arms(HANG, 0.05 * s), stance,
                                       {"spine": (-8, 0, 4 * s), "chest": (-5, 0, -4 * s), "head": (12, 8 * s, 14)}), st_off)
    # walk: limping shamble, right leg drags. 1.2 s loop, ~1.2 m/s at playback speed 1.
    acts.append(lib.new_action(ao, "walk"))
    for f, lg, off, s in (
        (0, legs(22, -6, -18, -22, 6, 12), 0, 1),
        (9, legs(2, -10, 6, -36, 0, 18), 0, 0),
        (18, legs(-20, -26, 15, -8, 10, 4), 0, -1),
        (27, legs(8, -52, 0, -10, 22, 0), 0, 0),
        (36, legs(22, -6, -18, -22, 6, 12), 0, 1),
    ):
        lib.key_pose(ao, f, lib.merge(sway_arms(REACH, 0.06 * s), SHAMBLE, lg, {"hips": (0, 3 * s, -3 * s)}), plant(lg))
    # run: lunging sprint. 0.67 s loop, ~3.8 m/s at playback speed 1.
    acts.append(lib.new_action(ao, "run"))
    run_upper = {"spine": (-24, 0, 0), "chest": (-10, 0, 0), "neck": (6, 0, 0), "head": (16, 0, 6)}
    hi_l = arms((0.2, 0.9, 0.25), (0.1, 0.9, 0.3), (0.05, 0.8, 0.4), (-0.3, 0.55, -0.7), (-0.2, 0.8, -0.4), (-0.1, 0.6, -0.7))
    hi_r = arms((0.3, 0.55, -0.7), (0.2, 0.8, -0.4), (0.1, 0.6, -0.7), (-0.2, 0.9, 0.25), (-0.1, 0.9, 0.3), (-0.05, 0.8, 0.4))
    for f, lg, off, a in (
        (0, legs(42, -15, -32, -70, 10, 20), -0.02, hi_r),
        (5, legs(10, -12, 2, -105, 0, 30), 0.03, REACH),
        (10, legs(-32, -70, 42, -15, 20, 10), -0.02, hi_l),
        (15, legs(2, -105, 10, -12, 30, 0), 0.03, REACH),
        (20, legs(42, -15, -32, -70, 10, 20), -0.02, hi_r),
    ):
        lib.key_pose(ao, f, lib.merge(run_upper, a, lg), plant(lg, off))
    # attack: arms up, slam down. Strike lands at frame 13 of 24.
    acts.append(lib.new_action(ao, "attack"))
    up = arms((0.25, 0.35, 0.9), (0.15, 0.55, 0.8), (0.1, 0.8, 0.6), (-0.25, 0.35, 0.9), (-0.15, 0.55, 0.8), (-0.1, 0.8, 0.6))
    down = arms((0.12, 0.75, -0.6), (0.04, 0.55, -0.85), (0.0, 0.3, -0.95), (-0.14, 0.72, -0.62), (-0.04, 0.5, -0.86), (0.0, 0.3, -0.95))
    lib.key_pose(ao, 0, lib.merge(REACH, SHAMBLE, stance), st_off)
    lib.key_pose(ao, 8, lib.merge(up, stance, {"spine": (6, 0, 0), "chest": (6, 0, 0), "head": (-6, 0, 0)}), st_off)
    lib.key_pose(ao, 13, lib.merge(down, legs(22, -22, -14, -10), {"spine": (-30, 0, 0), "chest": (-16, 0, 0), "head": (-10, 0, 0)}), plant(legs(22, -22, -14, -10), -0.02))
    lib.key_pose(ao, 24, lib.merge(REACH, SHAMBLE, stance), st_off)
    # hit: flinch back
    acts.append(lib.new_action(ao, "hit"))
    flung = arms((0.45, 0.2, -0.85), (0.4, 0.5, -0.7), (0.3, 0.4, -0.85), (-0.45, 0.2, -0.85), (-0.4, 0.5, -0.7), (-0.3, 0.4, -0.85))
    lib.key_pose(ao, 0, lib.merge(REACH, SHAMBLE, stance), st_off)
    lib.key_pose(ao, 3, lib.merge(flung, stance, {"spine": (16, 0, 8), "chest": (10, 0, 0), "head": (24, 0, 12)}), st_off)
    lib.key_pose(ao, 12, lib.merge(REACH, SHAMBLE, stance), st_off)
    # death: knees buckle, fall onto the back, arms splay on the floor
    acts.append(lib.new_action(ao, "death"))
    floor_arms = arms((0.85, 0.1, -0.1), (0.75, 0.45, -0.05), (0.6, 0.6, 0.0), (-0.8, -0.25, -0.1), (-0.6, -0.6, 0.0), (-0.4, -0.85, 0.0))
    lib.key_pose(ao, 0, lib.merge(REACH, SHAMBLE, stance), st_off)
    lib.key_pose(ao, 8, lib.merge(flung, legs(40, -72, 30, -60), {"spine": (12, 0, 4), "head": (20, 0, 10)}), (0, -0.05, -0.25))
    lib.key_pose(ao, 20, lib.merge(floor_arms, legs(10, -40, 5, -30), {"hips": (55, 0, 8), "head": (25, 0, 20)}), (0, -0.45, -0.55))
    lib.key_pose(ao, 30, lib.merge(floor_arms, legs(-2, -12, 2, -20, 30, 20), {"hips": (88, 0, 12), "head": (10, 25, 30)}), (0, -0.85, -0.84))
    lib.key_pose(ao, 40, lib.merge(floor_arms, legs(-2, -12, 2, -20, 30, 20), {"hips": (90, 0, 12), "head": (6, 30, 35)}), (0, -0.88, -0.86))
    lib.finish_actions(ao, acts)
    return acts


# ---------------------------------------------------------------- export / preview

def export(mesh_ob, ao, path):
    lib.activate(ao, mesh_ob)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='NLA_TRACKS',
        export_image_format='JPEG', export_jpeg_quality=86,
        export_skins=True, export_yup=True, export_apply=False,
    )


def preview(ao, out_png, action, frame, cam=(1.25, 2.9, 1.35), target=(0, 0.1, 0.95), lens=45):
    for o in [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT') or o.name.startswith("Plane")]:
        bpy.data.objects.remove(o, do_unlink=True)
    lib.render_setup((640, 800), samples=48)
    lib.add_camera(cam, target, lens=lens)
    lib.add_light('AREA', (1.8, 2.4, 2.6), 220, (1.0, 0.78, 0.55), size=1.6)
    lib.add_light('AREA', (-1.8, -1.4, 2.2), 600, (0.5, 0.62, 1.0), size=1.0)
    lib.add_light('POINT', (-1.0, 1.4, 0.5), 50, (1.0, 0.12, 0.08))
    bpy.ops.mesh.primitive_plane_add(size=10)
    floor = bpy.context.active_object
    floor.data.materials.append(lib.grunge_material("floor", "#2a2b2c", "#121314", blood_amount=0.12, scale=3))
    ao.animation_data.action = bpy.data.actions[action]
    bpy.context.scene.frame_set(frame)
    lib.render(out_png)
    ao.animation_data.action = None


def main():
    preview_dir = None
    if "--preview" in sys.argv:
        preview_dir = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview_dir, exist_ok=True)
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    os.makedirs(OUT_DIR, exist_ok=True)
    for i, variant in enumerate(("walker", "runner")):
        if only and variant != only:
            continue
        ob = build_variant(variant)
        texture(ob, variant, 100 + i * 37)
        scale = 0.94 if variant == "runner" else 1.0  # runner: gaunter, head ~1.53 m when running
        for v in ob.data.vertices:
            v.co *= scale
        LEG_SCALE[0] = scale
        ao = build_armature(ob, scale)
        build_actions(ao)
        print("%s: %d triangles" % (variant, lib.tri_count(ob)))
        export(ob, ao, os.path.join(OUT_DIR, "zombie_%s.glb" % variant))
        if preview_dir:
            loco = "run" if variant == "runner" else "walk"
            preview(ao, os.path.join(preview_dir, "zombie_%s_%s.png" % (variant, loco)), loco, 4)
            preview(ao, os.path.join(preview_dir, "zombie_%s_attack.png" % variant), "attack", 9)
            hz = 1.5 if variant == "runner" else 1.6
            preview(ao, os.path.join(preview_dir, "zombie_%s_face.png" % variant), "idle", 1,
                    cam=(0.22, 0.75, hz + 0.02), target=(0, 0, hz), lens=60)


if __name__ == "__main__":
    main()
