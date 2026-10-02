"""Operator character for other players in online play (art stage 4, v2).

Run:  /opt/blender-venv/bin/python art/blender/build_soldier.py [--preview DIR]
Output: client/assets/models/soldier.glb  (actions: idle, run, downed)

A covert-ops look in the spirit of the Black Ops series, all original:
high-cut helmet (rails, NVG mount, counterweight, IR strobe = cyan ally marker),
headset, full-face respirator with glass lenses and a side filter, plate carrier
(curved plates, cummerbund, mag pouches with magazines, admin pouch, radio with
antenna), assault pack, battle belt, drop-leg holster, cargo pockets, knee pads,
gloves and boots, tiger-stripe uniform. Textures: 2048 albedo, metallic/roughness,
and a tangent-space normal map baked from painted height (weave, MOLLE webbing,
seams, folds). Same 23-bone rig as the zombies; the arms are solved with a
two-bone IK onto the weapon the game hangs at eye height. Faces +Y (Godot -Z).
"""
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
import painter as pt  # noqa: E402
import build_zombies as bz  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "client", "assets", "models", "soldier.glb")
TEX = 2048

CATS = ["uniform", "head", "helmet", "mask", "lens", "gear", "webbing", "mag", "metal", "rubber", "pad", "patch", "mark"]
(UNIFORM, HEAD, HELMET, MASK, LENS, GEAR, WEBBING, MAG, METAL, RUBBER, PAD, PATCH, MARK) = range(len(CATS))
HC = bz.HEAD_C

# Third-person weapon holds. The game hangs the first-person weapon model with its
# Root reset (origin = trigger grip) at `pos` (Blender: x right, y forward, z up),
# scaled by `scale`; visuals.json -> players.soldier.holds must match these.
# Hand points are the viewmodel's own hands measured with Root at identity.
HOLDS = {
    "long":   {"pos": Vector((0.17, 0.31, 1.33)), "scale": 0.85, "support": Vector((-0.022, 0.34, 0.043))},
    "smg":    {"pos": Vector((0.16, 0.30, 1.32)), "scale": 0.9, "support": Vector((0.01, 0.141, -0.027))},
    "pistol": {"pos": Vector((0.06, 0.42, 1.34)), "scale": 0.95, "support": Vector((-0.005, 0.025, -0.036))},
}
GRIP = Vector((0.01, 0.032, -0.017))       # trigger hand (+X side, bones ".L")
ARM_K = 1.15                               # longer arms than the zombie rig (human reach)


# ---------------------------------------------------------------- body

def joints():
    """Zombie joint graph, re-proportioned: broad shoulders, full limbs (clothed),
    shorter thick gloved fingers curled to grip."""
    j = bz.joints("walker")
    scale = {"pelvis": 1.12, "waist": 1.1, "chest": 1.12, "upchest": 1.15, "neck": 1.45, "neck_top": 1.35,
             "clav.L": 1.15, "shoulder.L": 1.15, "bicep.L": 1.15, "elbow.L": 1.18, "fore.L": 1.15, "wrist.L": 1.15,
             "palm.L": 1.1, "hip.L": 1.1, "thigh_mid.L": 1.15, "knee.L": 1.2, "calf.L": 1.12, "shin_low.L": 1.12,
             "ankle.L": 1.35, "heel.L": 1.35, "toe.L": 1.3}
    out = {}
    for name, (p, r) in j.items():
        if name.startswith(("fing", "thumb")):
            continue
        k = scale.get(name, 1.0)
        out[name] = (p, (r[0] * k, r[1] * k))
    out["toe.L"] = ((0.1, 0.16, 0.045), (0.06, 0.045))
    for i, fy in enumerate((-0.022, -0.007, 0.008, 0.023)):  # gloved fingers, curled forward (grip)
        out["fing%d_a.L" % i] = ((0.568, 0.016 + fy * 0.3, 0.952 + fy * 0.2), (0.016, 0.015))
        out["fing%d_b.L" % i] = ((0.58, 0.05 + fy * 0.3, 0.938 + fy * 0.2), (0.014, 0.013))
        out["fing%d_c.L" % i] = ((0.565, 0.072 + fy * 0.3, 0.952 + fy * 0.2), (0.012, 0.011))
    out["thumb_a.L"] = ((0.53, 0.045, 0.99), (0.017, 0.016))
    out["thumb_b.L"] = ((0.54, 0.075, 0.975), (0.014, 0.013))
    # lengthen the arm from the shoulder (everything from the bicep down moves out)
    sh = Vector(out["shoulder.L"][0])
    for name in list(out):
        if name.startswith(("bicep", "elbow", "fore", "wrist", "palm", "fing", "thumb")):
            p, r = out[name]
            out[name] = (tuple(sh + (Vector(p) - sh) * ARM_K), r)
    return out


def long_arm_bones():
    """bz.BONES with the arm bones stretched like the joints (same shoulder)."""
    sh = Vector((0.2, -0.002, 1.425))
    out = []
    for name, h, t, parent in bz.BONES:
        if name in ("upper_arm.L", "forearm.L", "hand.L"):
            h = tuple(sh + (Vector(h) - sh) * ARM_K)
            t = tuple(sh + (Vector(t) - sh) * ARM_K)
        out.append((name, h, t, parent))
    return out


def build_body():
    j = joints()
    for name, (p, r) in list(j.items()):
        if name.endswith(".L"):
            j[bz._mirror_name(name)] = ((-p[0], p[1], p[2]), r)
    edges = list(bz.EDGES)
    edges += [(bz._mirror_name(a), bz._mirror_name(b)) for a, b in bz.EDGES if a.endswith(".L") or b.endswith(".L")]
    names = list(j.keys())
    me = bpy.data.meshes.new("body")
    me.from_pydata([j[n][0] for n in names], [(names.index(a), names.index(b)) for a, b in edges], [])
    ob = lib.link(bpy.data.objects.new("body", me))
    skin = ob.modifiers.new("skin", 'SKIN')
    skin.branch_smoothing = 0.6
    skin.use_smooth_shade = True
    for i, n in enumerate(names):
        sv = me.skin_vertices[0].data[i]
        sv.radius = j[n][1]
        sv.use_root = n == "pelvis"
    ob.modifiers.new("sub", 'SUBSURF').levels = 1
    lib.apply_modifiers(ob)
    return ob


# ---------------------------------------------------------------- modelling helpers

def finish(ob, cat, bone, smooth=True):
    ob["cat"] = cat
    ob["bone"] = bone
    for p in ob.data.polygons:
        p.use_smooth = smooth
    return ob


def apply_xf(ob):
    lib.activate(ob)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def rbox(name, center, size, cat, bone, r=0.25, rot=(0, 0, 0), segs=2):
    """Box with rounded edges; r = bevel as a fraction of the smallest side."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=[math.radians(a) for a in rot])
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    apply_xf(ob)
    m = ob.modifiers.new("bev", 'BEVEL')
    m.width = min(size) * r
    m.segments = segs
    lib.apply_modifiers(ob)
    lib.activate(ob)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    ob["cat"] = cat
    ob["bone"] = bone
    return ob


def cyl(name, a, b, r, cat, bone, verts=16, r2=None, bevel=0.0):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=d.length, location=(a + b) / 2)
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    apply_xf(ob)
    if bevel > 0:
        m = ob.modifiers.new("bev", 'BEVEL')
        m.width = bevel
        m.segments = 2
        lib.apply_modifiers(ob)
    lib.activate(ob)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(45))
    ob["cat"] = cat
    ob["bone"] = bone
    return ob


def torus(name, center, major, minor, cat, bone, scale=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=28, minor_segments=8, major_radius=major, minor_radius=minor,
                                     location=center, rotation=[math.radians(a) for a in rot])
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = scale
    apply_xf(ob)
    return finish(ob, cat, bone)


def band(name, z0, z1, rx, ry, cy, cat, bone, thick=0.012, seg=40, skip=None):
    """Open or closed elliptic band (cummerbund, belt, straps) with thickness."""
    bm = bmesh.new()
    rows = []
    for z in (z0, z1):
        rows.append([bm.verts.new((math.cos(2 * math.pi * i / seg) * rx, cy + math.sin(2 * math.pi * i / seg) * ry, z)) for i in range(seg)])
    for i in range(seg):
        if skip and skip(2 * math.pi * (i + 0.5) / seg):
            continue
        k = (i + 1) % seg
        bm.faces.new((rows[0][i], rows[0][k], rows[1][k], rows[1][i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = lib.link(bpy.data.objects.new(name, me))
    ob.modifiers.new("sol", 'SOLIDIFY').thickness = thick
    m = ob.modifiers.new("bev", 'BEVEL')
    m.width = thick * 0.4
    m.segments = 2
    lib.apply_modifiers(ob)
    return finish(ob, cat, bone)


def plate(name, center, w, h, wrap_r, thick, cat, bone, facing=1, corner=0.045, nx=14, nz=14):
    """Curved rounded-rectangle plate wrapped around a vertical axis behind it
    (armour plates). facing=+1 faces +Y, -1 faces -Y."""
    bm = bmesh.new()
    grid = []
    for iz in range(nz + 1):
        row = []
        for ix in range(nx + 1):
            u = (ix / nx - 0.5) * w
            v = (iz / nz - 0.5) * h
            cxr, czr = w / 2 - corner, h / 2 - corner
            du, dv = abs(u) - cxr, abs(v) - czr
            if du > 0 and dv > 0:
                d = math.hypot(du, dv)
                if d > corner:
                    u = math.copysign(cxr + du / d * corner, u)
                    v = math.copysign(czr + dv / d * corner, v)
            if v > h / 2 - 0.07 and abs(u) > w / 2 - 0.07:   # shooter's cut upper corners
                cut = (v - (h / 2 - 0.07)) * 0.9
                u = math.copysign(min(abs(u), w / 2 - cut), u)
            a = u / wrap_r
            x = wrap_r * math.sin(a)
            y = -wrap_r * (1 - math.cos(a))
            row.append(bm.verts.new((center[0] + x, center[1] + facing * y, center[2] + v)))
        grid.append(row)
    for iz in range(nz):
        for ix in range(nx):
            f = (grid[iz][ix], grid[iz][ix + 1], grid[iz + 1][ix + 1], grid[iz + 1][ix])
            bm.faces.new(f if facing > 0 else tuple(reversed(f)))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = lib.link(bpy.data.objects.new(name, me))
    sol = ob.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = thick
    sol.offset = -1
    m = ob.modifiers.new("bev", 'BEVEL')
    m.width = thick * 0.35
    m.segments = 2
    m.limit_method = 'ANGLE'
    lib.apply_modifiers(ob)
    return finish(ob, cat, bone)


# ---------------------------------------------------------------- gear

def helmet_parts():
    parts = []
    bpy.ops.mesh.primitive_uv_sphere_add(segments=44, ring_count=34, radius=1.0, location=(0, 0, 0))
    shell = bpy.context.active_object
    shell.name = "helmet"
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.45], context='VERTS')
    for v in bm.verts:  # pull everything below the cut line onto it: a clean high-cut rim
        x, y, z = v.co
        az = math.atan2(x, y)                      # 0 = front
        side = abs(math.sin(az))                   # 1 at the ears
        back = max(0.0, -math.cos(az))
        cut = -0.05 + 0.42 * side ** 3 - 0.15 * back
        if z < cut:
            r = math.sqrt(max(0.0, 1 - cut * cut))
            h = math.hypot(x, y) or 1.0
            v.co = Vector((x / h * r, y / h * r, cut))
    bm.to_mesh(shell.data)
    bm.free()
    for v in shell.data.vertices:
        v.co = Vector((v.co.x * 0.128, v.co.y * 0.142 - 0.006, v.co.z * 0.118)) + Vector((HC.x, HC.y, HC.z + 0.03))
    sol = shell.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = 0.012
    m = shell.modifiers.new("bev", 'BEVEL')
    m.width = 0.004
    m.segments = 2
    lib.apply_modifiers(shell)
    parts.append(finish(shell, HELMET, "head"))
    top = HC.z + 0.03
    parts.append(rbox("nvg_shroud", (0, HC.y + 0.14, top + 0.045), (0.055, 0.02, 0.045), METAL, "head", r=0.3))
    parts.append(rbox("nvg_arm", (0, HC.y + 0.165, top + 0.03), (0.03, 0.03, 0.03), METAL, "head", r=0.3))
    for sx in (-1, 1):
        parts.append(rbox("rail", (sx * 0.126, HC.y + 0.005, top + 0.02), (0.012, 0.12, 0.02), METAL, "head", r=0.25))
        parts.append(cyl("cup", (sx * 0.1, HC.y - 0.005, HC.z - 0.005), (sx * 0.135, HC.y - 0.005, HC.z - 0.005), 0.036, RUBBER, "head", verts=20, bevel=0.006))
    parts.append(cyl("mic", (0.12, HC.y + 0.03, HC.z - 0.03), (0.06, HC.y + 0.11, HC.z - 0.07), 0.004, METAL, "head", verts=6))
    parts.append(rbox("counterweight", (0, HC.y - 0.15, top - 0.02), (0.09, 0.03, 0.06), GEAR, "head", r=0.35))
    parts.append(rbox("velcro", (0, HC.y + 0.02, top + 0.115), (0.07, 0.09, 0.008), PATCH, "head", r=0.4))
    parts.append(cyl("strobe", (0, HC.y - 0.08, top + 0.1), (0, HC.y - 0.09, top + 0.125), 0.018, METAL, "head", verts=12))
    parts.append(rbox("marker", (0, HC.y - 0.09, top + 0.132), (0.024, 0.016, 0.008), MARK, "head", r=0.4))
    return parts


def mask_parts():
    """Full-face respirator: rubber face piece, two glass lenses, side filter, valve."""
    parts = []
    bpy.ops.mesh.primitive_uv_sphere_add(segments=36, ring_count=24, radius=1.0)
    m = bpy.context.active_object
    m.name = "mask"
    bm = bmesh.new()
    bm.from_mesh(m.data)
    kill = [v for v in bm.verts if v.co.y < 0.05 or v.co.z > 0.55 or v.co.z < -0.92]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(m.data)
    bm.free()
    for v in m.data.vertices:
        x, y, z = v.co
        p = Vector((x * 0.105, y * 0.122, z * 0.13))
        snout = max(0.0, 1 - math.hypot(x * 1.6, (z + 0.55) * 1.6))      # filter snout below the nose
        p.y += 0.035 * snout ** 1.5
        p.x *= 1.0 - 0.15 * max(0.0, -z - 0.4)                          # narrower chin
        v.co = p + Vector((HC.x, HC.y + 0.012, HC.z - 0.005))
    sol = m.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = 0.008
    lib.apply_modifiers(m)
    parts.append(finish(m, MASK, "head"))
    for sx in (-1, 1):
        c = Vector((sx * 0.04, HC.y + 0.13, HC.z + 0.012))
        n = Vector((sx * 0.3, 1.0, 0.05)).normalized()
        parts.append(cyl("lens_rim", c - n * 0.012, c + n * 0.012, 0.031, METAL, "head", verts=24, bevel=0.004))
        parts.append(cyl("lens", c + n * 0.008, c + n * 0.0135, 0.025, LENS, "head", verts=24))
    fc = Vector((0.07, HC.y + 0.1, HC.z - 0.085))            # filter canister on the cheek
    fd = Vector((0.75, 0.55, -0.25)).normalized()
    parts.append(cyl("filter_neck", fc - fd * 0.01, fc + fd * 0.02, 0.022, RUBBER, "head", verts=20))
    parts.append(cyl("filter", fc + fd * 0.02, fc + fd * 0.075, 0.038, GEAR, "head", verts=24, bevel=0.004))
    rot = tuple(math.degrees(a) for a in fd.to_track_quat('Z', 'Y').to_euler())
    for k in range(3):
        parts.append(torus("filter_rib", tuple(fc + fd * (0.032 + k * 0.017)), 0.038, 0.003, METAL, "head", rot=rot))
    vc = Vector((0, HC.y + 0.15, HC.z - 0.075))
    parts.append(cyl("valve", vc - Vector((0, 0.01, 0)), vc + Vector((0, 0.022, -0.006)), 0.026, RUBBER, "head", verts=20, bevel=0.004))
    parts.append(cyl("voicemitter", vc + Vector((0, 0.022, -0.006)), vc + Vector((0, 0.028, -0.008)), 0.018, METAL, "head", verts=20))
    for z, rx in ((HC.z + 0.03, 0.112), (HC.z - 0.06, 0.104)):     # head harness straps
        parts.append(band("strap", z - 0.008, z + 0.008, rx, 0.118, HC.y - 0.005, WEBBING, "head", thick=0.004,
                          skip=lambda a: math.sin(a) > 0.35))
    return parts


def carrier_parts():
    parts = []
    parts.append(plate("front_plate", (0, 0.17, 1.27), 0.33, 0.36, 0.42, 0.05, GEAR, "chest", facing=1))
    parts.append(plate("back_plate", (0, -0.158, 1.29), 0.33, 0.38, 0.42, 0.05, GEAR, "chest", facing=-1))
    parts.append(band("cummerbund", 1.12, 1.27, 0.215, 0.155, 0.005, WEBBING, "chest", thick=0.018,
                      skip=lambda a: abs(math.cos(a)) < 0.55))
    for sx in (-1, 1):                     # padded shoulder straps over the trapezius
        pts = [(sx * 0.105, 0.16, 1.45), (sx * 0.12, 0.09, 1.5), (sx * 0.125, 0.0, 1.515), (sx * 0.12, -0.09, 1.5), (sx * 0.105, -0.15, 1.46)]
        for a, b in zip(pts, pts[1:]):
            a, b = Vector(a), Vector(b)
            mid = (a + b) / 2
            d = b - a
            ang = math.degrees(math.atan2(d.z, d.y))
            parts.append(rbox("shoulder_strap", tuple(mid), (0.06, d.length + 0.02, 0.018), WEBBING, "chest", r=0.4, rot=(-ang, 0, 0)))
    for x in (-0.075, 0.0, 0.075):          # triple magazine pouch with magazines
        parts.append(rbox("mag_pouch", (x, 0.228, 1.17), (0.066, 0.05, 0.11), WEBBING, "chest", r=0.18))
        parts.append(rbox("mag", (x, 0.228, 1.255), (0.05, 0.026, 0.07), MAG, "chest", r=0.15, rot=(8, 0, 0)))
        parts.append(rbox("bungee", (x, 0.255, 1.24), (0.04, 0.006, 0.008), RUBBER, "chest", r=0.4))
    parts.append(rbox("admin_pouch", (0, 0.212, 1.36), (0.2, 0.035, 0.085), GEAR, "chest", r=0.25))
    parts.append(rbox("name_patch", (-0.05, 0.232, 1.372), (0.075, 0.006, 0.03), PATCH, "chest", r=0.4))
    parts.append(rbox("flag_patch", (0.055, 0.232, 1.372), (0.06, 0.006, 0.035), PATCH, "chest", r=0.4))
    parts.append(rbox("radio_pouch", (-0.215, 0.03, 1.22), (0.055, 0.075, 0.13), WEBBING, "chest", r=0.2))
    parts.append(rbox("radio", (-0.215, 0.03, 1.31), (0.045, 0.06, 0.06), METAL, "chest", r=0.2))
    parts.append(cyl("antenna", (-0.215, 0.0, 1.33), (-0.2, -0.05, 1.62), 0.004, RUBBER, "chest", verts=6))
    parts.append(cyl("antenna_tip", (-0.2, -0.05, 1.62), (-0.19, -0.075, 1.78), 0.0025, RUBBER, "chest", verts=6))
    parts.append(cyl("flashbang_pouch", (0.215, 0.06, 1.12), (0.215, 0.06, 1.24), 0.03, WEBBING, "chest", verts=16, bevel=0.005))
    parts.append(cyl("flashbang", (0.215, 0.06, 1.24), (0.215, 0.06, 1.27), 0.024, METAL, "chest", verts=16))
    parts.append(rbox("pack", (0, -0.245, 1.28), (0.27, 0.12, 0.34), GEAR, "chest", r=0.3, segs=3))
    parts.append(rbox("pack_pocket", (0, -0.31, 1.22), (0.2, 0.04, 0.16), WEBBING, "chest", r=0.3))
    for sx in (-1, 1):
        parts.append(rbox("compression", (sx * 0.1, -0.307, 1.3), (0.02, 0.012, 0.3), WEBBING, "chest", r=0.4))
    tube = [(0.09, -0.2, 1.46), (0.13, -0.05, 1.53), (0.14, 0.1, 1.5), (0.13, 0.19, 1.4)]
    for a, b in zip(tube, tube[1:]):
        parts.append(cyl("tube", a, b, 0.007, RUBBER, "chest", verts=8))
    return parts


def belt_parts():
    parts = [band("belt", 0.94, 1.0, 0.185, 0.135, 0.0, WEBBING, "hips", thick=0.02)]
    parts.append(rbox("buckle", (0, 0.142, 0.97), (0.06, 0.012, 0.045), METAL, "hips", r=0.3))
    for x, y, s in ((0.13, 0.11, (0.05, 0.04, 0.08)), (-0.13, 0.11, (0.05, 0.04, 0.08)), (0.17, -0.07, (0.05, 0.08, 0.1)),
                    (-0.16, -0.08, (0.06, 0.09, 0.12))):
        parts.append(rbox("belt_pouch", (x, y, 0.94), s, WEBBING, "hips", r=0.25))
    parts.append(rbox("holster_strap", (0.165, 0.0, 0.84), (0.03, 0.04, 0.16), WEBBING, "thigh.L", r=0.3))
    parts.append(rbox("holster", (0.178, 0.02, 0.73), (0.045, 0.1, 0.19), GEAR, "thigh.L", r=0.25))
    parts.append(rbox("pistol_grip", (0.178, -0.035, 0.84), (0.032, 0.035, 0.07), MAG, "thigh.L", r=0.3, rot=(-15, 0, 0)))
    parts.append(rbox("cargo", (-0.165, 0.01, 0.7), (0.035, 0.13, 0.15), UNIFORM, "thigh.R", r=0.3))
    return parts


def limb_parts():
    parts = []
    for sx, shin, foot, arm, hand in ((1, "shin.L", "foot.L", "upper_arm.L", "hand.L"), (-1, "shin.R", "foot.R", "upper_arm.R", "hand.R")):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=1.0, location=(0, 0, 0))
        kp = bpy.context.active_object
        kp.name = "kneepad"
        bm = bmesh.new()
        bm.from_mesh(kp.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.1], context='VERTS')
        bm.to_mesh(kp.data)
        bm.free()
        for v in kp.data.vertices:
            v.co = Vector((v.co.x * 0.075 + sx * 0.1, v.co.y * 0.05 + 0.055, v.co.z * 0.095 + 0.53))
        kp.modifiers.new("sol", 'SOLIDIFY').thickness = 0.01
        lib.apply_modifiers(kp)
        parts.append(finish(kp, PAD, shin))
        parts.append(rbox("arm_patch", (sx * 0.29, 0.0, 1.31), (0.012, 0.06, 0.055), PATCH, arm, r=0.4, rot=(0, sx * 32, 0)))
        kn = Vector((0.2, -0.002, 1.425)) + (Vector((0.555, 0.05, 0.965)) - Vector((0.2, -0.002, 1.425))) * ARM_K
        parts.append(rbox("knuckles", (sx * kn.x, kn.y, kn.z), (0.02, 0.05, 0.035), PAD, hand, r=0.4))
    return parts


# ---------------------------------------------------------------- assembly

def build():
    lib.reset()
    mats = [lib.flat_material(n, "#808080") for n in CATS]

    def assign(ob, cat):
        ob.data.materials.clear()
        for m in mats:
            ob.data.materials.append(m)
        for p in ob.data.polygons:
            p.material_index = cat
    body = build_body()
    head = bz.build_head(mouth_open=0.0)
    assign(body, UNIFORM)
    assign(head, HEAD)
    base = lib.join([body, head], "soldier")
    rigid = helmet_parts() + mask_parts() + carrier_parts() + belt_parts() + limb_parts()
    for ob in rigid:
        assign(ob, int(ob["cat"]))
    return base, rigid


def attach_rigid(base, rigid):
    """Gear moves rigidly with one bone each; joined into the skinned mesh."""
    for ob in rigid:
        ob.vertex_groups.new(name=str(ob["bone"])).add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
    return lib.join([base] + rigid, "soldier")


# ---------------------------------------------------------------- texturing

def fold_height(P):
    """Cloth folds: bands around the knees/elbows/waist plus soft noise."""
    x, z = P[:, 0], P[:, 2]
    n = pt.fbm(P, 9, 3, 51)
    knee = np.exp(-((z - 0.53) / 0.09) ** 2) * (np.abs(x) < 0.2)
    elbow = np.exp(-(np.hypot(np.abs(x) - 0.352, z - 1.215) / 0.07) ** 2)
    waist = np.exp(-((z - 1.04) / 0.05) ** 2)
    f = np.sin(z * 120 + n * 8) * (0.5 * knee + 0.5 * elbow) + np.sin(z * 80 + n * 5) * 0.3 * waist
    return 0.5 * f + 0.6 * (n - 0.5)


def paint(P, part, edges):
    N = len(P)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    rough = np.full(N, 0.85, np.float32)
    metal = np.zeros(N, np.float32)
    height = np.zeros(N, np.float32)
    col = np.zeros((N, 3), np.float32)
    weave = (np.sin(x * 2600) * np.sin(z * 2600) + np.sin(y * 2600) * np.sin(z * 2600)) * 0.5
    grime = pt.smooth(0.5, 0.85, pt.fbm(P, 4, 3, 7))
    wear = pt.smooth(0.5, 0.95, edges)
    n1 = pt.fbm(P, 8, 4, 3)
    zero = np.zeros(N, np.float32)

    # uniform: dark tiger stripe (horizontal brush strokes), seams, dirt low on the legs
    Q = P * np.array([3.0, 3.0, 11.0], np.float32)
    stripe = pt.fbm(Q, 1, 4, 11)
    stripe2 = pt.fbm(Q * 1.7 + 5, 1, 3, 19)
    camo = np.tile(pt.hexc("#3d4136"), (N, 1))
    camo = pt.lerp(camo, pt.hexc("#5a5640"), pt.smooth(0.56, 0.6, stripe2) * 0.75)
    camo = pt.lerp(camo, pt.hexc("#131512"), pt.smooth(0.51, 0.54, stripe))
    camo = camo * (0.93 + 0.07 * weave)[:, None]
    seam = (np.abs(np.mod(z * 7.0 + 0.3, 1.0) - 0.5) < 0.012) | (np.abs(x) < 0.004)
    camo = np.where(seam[:, None], camo * 0.7, camo)
    camo = pt.lerp(camo, pt.hexc("#3b342a"), np.clip(pt.smooth(0.45, 0.05, z) * 0.6 + grime * 0.25, 0, 1))
    boots = z < 0.2
    gloves = (np.abs(x) > 0.47) & (z < 1.1)
    neck = (z > 1.45) & (np.abs(x) < 0.12)
    unif = np.where(boots[:, None], pt.lerp(pt.hexc("#1f1d1a"), pt.hexc("#33302a"), n1), camo)
    unif = np.where(gloves[:, None], pt.lerp(pt.hexc("#202022"), pt.hexc("#2d2d30"), n1), unif)
    unif = np.where(neck[:, None], pt.lerp(pt.hexc("#1c1d1f"), pt.hexc("#26282a"), n1), unif)  # neck gaiter
    lace = boots & (y > 0.06) & (np.abs(np.mod(z * 40, 1.0) - 0.5) < 0.12) & (np.abs(np.abs(x) - 0.1) < 0.025)
    unif = np.where(lace[:, None], unif * 0.55, unif)
    uh = weave * 0.25 + fold_height(P) - seam * 0.6

    head = pt.lerp(pt.hexc("#1b1c1e"), pt.hexc("#26272a"), n1) * (0.94 + 0.06 * weave)[:, None]   # balaclava

    # MOLLE webbing: rows of tape with bar-tack stitches
    tape = np.mod(z / 0.038, 1.0) < 0.66
    az = np.arctan2(x, y + 0.0001) * 0.2 + x
    tack = np.abs(np.mod(az / 0.04, 1.0) - 0.5) < 0.07
    web_base = pt.lerp(pt.hexc("#7a6a4c"), pt.hexc("#5f523b"), n1)   # coyote
    web = np.where(tape[:, None], web_base * 1.08, web_base * 0.72)
    web = np.where((tape & tack)[:, None], web * 0.7, web)
    web = pt.lerp(web, pt.hexc("#a39477"), wear * 0.35)
    wh = tape * 0.6 - (tape & tack) * 0.3 + weave * 0.15
    gear = pt.lerp(pt.hexc("#6f6146"), pt.hexc("#574b36"), n1) * (0.95 + 0.05 * weave)[:, None]   # coyote
    gear = pt.lerp(gear, pt.hexc("#9a8c6c"), wear * 0.4)
    gear = pt.lerp(gear, pt.hexc("#1f1c17"), grime * 0.25)

    helmet = pt.lerp(pt.hexc("#262826"), pt.hexc("#1b1c1b"), n1)
    helmet = pt.lerp(helmet, pt.hexc("#6a6c66"), wear * 0.5)
    hh = (pt.fbm(P, 60, 2, 71) - 0.5) * 0.3
    mask = pt.lerp(pt.hexc("#151617"), pt.hexc("#1e1f21"), n1)
    metal_c = pt.lerp(pt.hexc("#2a2b2d"), pt.hexc("#3b3c3f"), n1)
    metal_c = pt.lerp(metal_c, pt.hexc("#8c8f93"), wear * 0.6)
    mag_c = pt.lerp(pt.hexc("#26272a"), pt.hexc("#1a1b1d"), n1)
    mag_c = pt.lerp(mag_c, pt.hexc("#7d8085"), wear * 0.5)
    rubber = pt.lerp(pt.hexc("#141414"), pt.hexc("#1d1d1e"), n1)
    pad = pt.lerp(pt.hexc("#232522"), pt.hexc("#2e302c"), n1)
    pad = pt.lerp(pad, pt.hexc("#5d5e58"), wear * 0.5)
    patch = pt.lerp(pt.hexc("#4a4c40"), pt.hexc("#3a3c32"), pt.fbm(P, 90, 2, 5))   # velcro loop texture

    table = {
        UNIFORM: (unif, 0.88, 0.0, uh), HEAD: (head, 0.9, 0.0, weave * 0.3),
        HELMET: (helmet, 0.62, 0.0, hh), MASK: (mask, 0.45, 0.0, (pt.fbm(P, 40, 2, 3) - 0.5) * 0.2),
        LENS: (np.tile(pt.hexc("#0b1a1c"), (N, 1)), 0.05, 0.6, zero),
        GEAR: (gear, 0.85, 0.0, weave * 0.25 + (n1 - 0.5) * 0.3), WEBBING: (web, 0.85, 0.0, wh),
        MAG: (mag_c, 0.4, 0.7, zero), METAL: (metal_c, 0.4, 0.8, zero),
        RUBBER: (rubber, 0.7, 0.0, (pt.fbm(P, 80, 2, 9) - 0.5) * 0.2), PAD: (pad, 0.55, 0.0, zero),
        PATCH: (patch, 0.95, 0.0, (pt.fbm(P, 120, 2, 13) - 0.5) * 0.6),
        MARK: (np.tile(pt.hexc("#38e8ff"), (N, 1)), 0.3, 0.0, zero),
    }
    for cat, (c, r, m, h) in table.items():
        sel = part == cat
        col[sel] = c[sel]
        rough[sel] = r
        metal[sel] = m
        height[sel] = h[sel]
    return np.clip(col, 0, 1), rough, metal, height


def bake_normal_from_height(ob, height_img, size, strength=0.6):
    """Tangent-space normal map from the painted height (Cycles bakes the bumped
    shading normal), so weave, webbing and seams catch the light."""
    nimg = bpy.data.images.new("soldier_normal", size, size)
    nimg.colorspace_settings.name = 'Non-Color'
    saved = [s.material for s in ob.material_slots]
    tmp = bpy.data.materials.new("__bump__")
    tmp.use_nodes = True
    nt = tmp.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    h = nt.nodes.new("ShaderNodeTexImage")
    h.image = height_img
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = 0.002
    nt.links.new(h.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    target = nt.nodes.new("ShaderNodeTexImage")
    target.image = nimg
    nt.nodes.active = target
    for i in range(len(ob.material_slots)):
        ob.material_slots[i].material = tmp
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 4
    sc.render.bake.margin = 4
    sc.render.bake.normal_space = 'TANGENT'
    lib.activate(ob)
    bpy.ops.object.bake(type='NORMAL')
    for i, m in enumerate(saved):
        ob.material_slots[i].material = m
    bpy.data.materials.remove(tmp)
    nimg.pack()
    return nimg


def texture(ob):
    head_v = set()
    for p in ob.data.polygons:
        if p.material_index in (HEAD, HELMET, MASK, LENS):
            head_v.update(p.vertices)
    saved = {i: ob.data.vertices[i].co.copy() for i in head_v}
    for i in head_v:  # the head is seen up close: more texels
        ob.data.vertices[i].co = HC + (saved[i] - HC) * 1.5
    lib.activate(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.004)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003, shape_method='CONCAVE')
    bpy.ops.object.mode_set(mode='OBJECT')
    for i, co in saved.items():
        ob.data.vertices[i].co = co
    edges = lib.bake_pointiness(ob, TEX)
    ao = lib.bake_ao(ob, TEX, samples=32)
    pos, nor, part, valid = pt.rasterize(ob, TEX)
    c, r, m, h = paint(pos[valid], part[valid], edges[valid])
    rgb = np.zeros((TEX, TEX, 3), np.float32)
    orm = np.zeros((TEX, TEX, 3), np.float32)
    hgt = np.zeros((TEX, TEX, 3), np.float32)
    rgb[valid] = c * (0.35 + 0.65 * ao[valid])[:, None]
    orm[valid] = np.stack([ao[valid], r, m], 1)
    hgt[valid] = np.repeat((0.5 + 0.5 * np.clip(h, -1, 1))[:, None], 3, 1)
    albedo = pt.to_image(bpy, "soldier_albedo", rgb, valid)
    orm_img = pt.to_image(bpy, "soldier_orm", orm, valid, non_color=True)
    h_img = pt.to_image(bpy, "soldier_height", hgt, valid, non_color=True)
    mat = lib.pbr_material("soldier", albedo, orm_img)
    for i in range(len(ob.data.materials)):
        ob.data.materials[i] = mat
    nimg = bake_normal_from_height(ob, h_img, TEX)
    nt = mat.node_tree
    nm = nt.nodes.new("ShaderNodeNormalMap")
    ntex = nt.nodes.new("ShaderNodeTexImage")
    ntex.image = nimg
    nt.links.new(ntex.outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], nt.nodes["Principled BSDF"].inputs["Normal"])
    lens = lib.flat_material("soldier_lens", "#0d2224", roughness=0.08, metallic=0.6)
    mark = lib.flat_material("ally_marker", "#38e8ff", emission="#38e8ff", strength=6.0)
    for i in range(len(ob.data.materials)):
        ob.data.materials[i] = lens if i == LENS else (mark if i == MARK else mat)


# ---------------------------------------------------------------- animation (IK onto the held weapon)

def weapon_point(hold_name, p):
    h = HOLDS[hold_name]
    return h["pos"] + p * h["scale"]


def ik_arm(ao, side, target, pole):
    pb = ao.pose.bones
    s = pb["upper_arm." + side].head.copy()
    l1 = (pb["upper_arm." + side].bone.tail_local - pb["upper_arm." + side].bone.head_local).length
    l2 = (pb["forearm." + side].bone.tail_local - pb["forearm." + side].bone.head_local).length
    d_vec = target - s
    d = min(d_vec.length, (l1 + l2) * 0.999)
    dirn = d_vec.normalized()
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    perp = (pole - dirn * pole.dot(dirn)).normalized()
    elbow = s + dirn * a + perp * h
    hand_end = s + dirn * d
    return {"upper_arm." + side: {"aim": tuple(elbow - s)}, "forearm." + side: {"aim": tuple(hand_end - elbow)},
            "hand." + side: {"aim": (0.0, 1.0, -0.15)}}


def hold(ao, body_rots, hips_offset, hold_name):
    lib.set_pose(ao, body_rots, hips_offset)
    bpy.context.view_layer.update()
    grip = weapon_point(hold_name, GRIP) - Vector((0, 0.06, 0.0))           # wrist sits behind the palm
    fore = weapon_point(hold_name, HOLDS[hold_name]["support"]) - Vector((0.0, 0.06, 0.01))
    arms = lib.merge(ik_arm(ao, "L", grip, Vector((0.6, -0.1, -0.8))), ik_arm(ao, "R", fore, Vector((-0.7, 0.0, -0.7))))
    return lib.merge(body_rots, arms)


STANCE_UP = {"spine": (2, 0, -10), "chest": (0, 0, -14), "neck": (0, 0, 10), "head": (-4, 0, 16)}


def build_actions(ao):
    acts = []
    stance = bz.legs(8, -10, -6, -10)
    off = bz.plant(stance)
    run_up = {"spine": (-12, 0, -10), "chest": (-4, 0, -14), "neck": (8, 0, 10), "head": (10, 0, 14)}
    for hold_name in HOLDS:
        twist = STANCE_UP if hold_name != "pistol" else {"spine": (2, 0, -3), "chest": (0, 0, -3), "neck": (0, 0, 3), "head": (-4, 0, 4)}
        acts.append(lib.new_action(ao, "idle_" + hold_name))
        for f, breathe in ((0, 0), (30, 1), (60, 0)):
            up = lib.merge(twist, {"chest": (-1.5 * breathe, 0, twist["chest"][2])})
            lib.key_pose(ao, f, hold(ao, lib.merge(up, stance), off, hold_name), off)
        acts.append(lib.new_action(ao, "run_" + hold_name))
        for f, lg, o in (
            (0, bz.legs(38, -18, -28, -60, 10, 20), -0.02),
            (5, bz.legs(10, -14, 4, -95, 0, 25), 0.03),
            (10, bz.legs(-28, -60, 38, -18, 20, 10), -0.02),
            (15, bz.legs(4, -95, 10, -14, 25, 0), 0.03),
            (20, bz.legs(38, -18, -28, -60, 10, 20), -0.02),
        ):
            off_r = bz.plant(lg, o)
            ru = run_up if hold_name != "pistol" else lib.merge(run_up, {"spine": (-12, 0, -3), "chest": (-4, 0, -3)})
            lib.key_pose(ao, f, hold(ao, lib.merge(ru, lg), off_r, hold_name), off_r)
    acts.append(lib.new_action(ao, "downed"))
    floor_arms = bz.arms((0.85, 0.1, -0.1), (0.75, 0.45, -0.05), (0.6, 0.6, 0.0), (-0.6, -0.5, -0.3), (-0.3, 0.2, 0.9), (0.0, 0.3, 0.95))
    pose = lib.merge(floor_arms, bz.legs(-2, -14, 6, -40, 30, 20), {"hips": (75, 0, 8), "spine": (-12, 0, 0), "head": (-20, 10, 10)})
    lib.key_pose(ao, 0, pose, (0, -0.75, -0.8))
    lib.key_pose(ao, 40, lib.merge(pose, {"head": (-24, -6, 10)}), (0, -0.75, -0.8))
    lib.finish_actions(ao, acts)
    return acts


# ---------------------------------------------------------------- preview

def preview(ao, out_png, act, frame, cam, target, lens=45, res=(900, 1100)):
    for o in [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT') or o.name.startswith("Plane")]:
        bpy.data.objects.remove(o, do_unlink=True)
    lib.render_setup(res, samples=48)
    w = bpy.context.scene.world.node_tree.nodes["Background"]
    w.inputs[0].default_value = (0.05, 0.055, 0.07, 1)
    w.inputs[1].default_value = 0.6
    lib.add_camera(cam, target, lens=lens)
    lib.add_light('AREA', (2.0, 2.6, 2.8), 130, (1.0, 0.9, 0.78), size=1.8)       # key
    lib.add_light('AREA', (-2.4, 0.8, 1.8), 45, (0.6, 0.7, 1.0), size=1.2)        # fill
    lib.add_light('AREA', (0.4, -2.6, 2.4), 200, (0.75, 0.6, 1.0), size=1.0)      # violet rim
    bpy.context.scene.view_settings.look = 'None'
    bpy.ops.mesh.primitive_plane_add(size=12)
    floor = bpy.context.active_object
    floor.data.materials.append(lib.grunge_material("floor", "#34353a", "#1b1c20", blood_amount=0.0, scale=4))
    ao.animation_data.action = act
    bpy.context.scene.frame_set(frame)
    lib.render(out_png)
    ao.animation_data.action = None


def gun_proxy(weapon="rifle", hold_name="long"):
    """The weapon exactly as the game hangs it (Root reset, at the hold, scaled)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "client", "assets", "models", "vm_%s.glb" % weapon))
    h = HOLDS[hold_name]
    for o in set(bpy.data.objects) - before:
        o.animation_data_clear()
        if o.type == 'MESH' and o.name.startswith("Arm"):
            o.hide_render = True
        if o.parent is None:
            o.matrix_basis = Matrix.Translation(h["pos"]) @ Matrix.Scale(h["scale"], 4)
    bpy.context.view_layer.update()


def main():
    base, rigid = build()
    bz.fix_part_weights = lambda ob: None   # rigid gear is weighted explicitly
    bz.BONES = long_arm_bones()
    ao = bz.build_armature(base)
    ob = attach_rigid(base, rigid)
    texture(ob)
    build_actions(ao)
    for o in list(bpy.data.objects):
        if o not in (ob, ao):
            bpy.data.objects.remove(o, do_unlink=True)
    print("soldier: %d triangles" % lib.tri_count(ob))
    bz.export(ob, ao, OUT)
    if "--preview" in sys.argv:
        d = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        lib.reset()
        bpy.ops.import_scene.gltf(filepath=OUT)
        ao = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
        acts = {a.name: a for a in bpy.data.actions}
        gun_proxy("rifle", "long")
        preview(ao, os.path.join(d, "soldier_front.png"), acts["idle_long"], 1, (1.3, 2.7, 1.55), (0, 0.1, 1.0))
        preview(ao, os.path.join(d, "soldier_back.png"), acts["idle_long"], 1, (-1.6, -2.4, 1.6), (0, 0, 1.05))
        preview(ao, os.path.join(d, "soldier_side.png"), acts["idle_long"], 1, (2.8, 0.6, 1.4), (0, 0.15, 1.0))
        preview(ao, os.path.join(d, "soldier_run.png"), acts["run_long"], 5, (2.6, 1.0, 1.3), (0, 0.1, 0.95))
        preview(ao, os.path.join(d, "soldier_head.png"), acts["idle_long"], 1, (0.45, 0.85, 1.75), (0, 0.05, 1.62), lens=70, res=(900, 900))


if __name__ == "__main__":
    main()
