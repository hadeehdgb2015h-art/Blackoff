"""First-person weapon viewmodels (weapon + gloved arms) for Blackoff.

Run:  /opt/blender-venv/bin/python art/blender/build_weapons.py [--only rifle] [--preview DIR]
Output: client/assets/models/vm_<id>.glb

Space: the GLB origin is the CAMERA. Blender +Y = forward (glTF/Godot -Z), +Z up,
+X right. The game parents the model to the camera and scales it uniformly
(about the camera), which keeps the image identical while pulling it out of
walls. Nodes: Root (animated) > Weapon, Mag, Slide, ArmR, ArmL, Muzzle.
Animations: idle, fire, reload (normalised; the game time-scales it), draw.
"""
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
import painter as pt  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "client", "assets", "models")
TEX = 1024
METAL, POLY, ACCENT, GLOVE, SLEEVE, EMIT, BRASS, LENS = range(8)
MAT_NAMES = ["metal", "poly", "accent", "glove", "sleeve", "emit", "brass", "lens"]


# ---------------------------------------------------------------- modelling kit (gun space: grip at origin)

class Kit:
    def __init__(self):
        self.parts = []
        self.mats = [lib.flat_material(n, "#808080") for n in MAT_NAMES]

    def _finish(self, ob, node, mat, bevel, smooth_angle=35):
        lib.activate(ob)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        if bevel > 0:
            m = ob.modifiers.new("bev", 'BEVEL')
            m.width = bevel
            m.segments = 2
            m.limit_method = 'ANGLE'
            m.angle_limit = math.radians(30)
            m.harden_normals = True
            lib.apply_modifiers(ob)
        ob.data.materials.clear()
        for mm in self.mats:
            ob.data.materials.append(mm)
        for p in ob.data.polygons:
            p.material_index = mat
        lib.activate(ob)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle))
        vg = ob.vertex_groups.new(name="node_" + node)
        vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
        self.parts.append(ob)
        return ob

    def box(self, node, mat, center, size, bevel=0.0015, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=[math.radians(r) for r in rot])
        ob = bpy.context.active_object
        ob.scale = size
        return self._finish(ob, node, mat, bevel)

    def cyl(self, node, mat, a, b, r, verts=16, bevel=0.001, r2=None):
        """Cylinder from point a to point b (gun space)."""
        a, b = Vector(a), Vector(b)
        d = b - a
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2 if r2 is not None else r, depth=d.length,
                                        location=(a + b) / 2)
        ob = bpy.context.active_object
        ob.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        return self._finish(ob, node, mat, bevel, smooth_angle=50)

    def sphere(self, node, mat, c, r, scale=(1, 1, 1), segs=12):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=max(6, segs // 2), radius=r, location=c)
        ob = bpy.context.active_object
        ob.scale = scale
        return self._finish(ob, node, mat, 0, smooth_angle=80)

    def prism(self, node, mat, profile, width, x=0.0, bevel=0.002):
        """Side profile [(y, z), ...] (counter-clockwise) extruded along X."""
        bm = bmesh.new()
        lo = [bm.verts.new((x - width / 2, y, z)) for y, z in profile]
        hi = [bm.verts.new((x + width / 2, y, z)) for y, z in profile]
        bm.faces.new(list(reversed(lo)))
        bm.faces.new(hi)
        n = len(profile)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new(node)
        bm.to_mesh(me)
        bm.free()
        ob = lib.link(bpy.data.objects.new(node, me))
        return self._finish(ob, node, mat, bevel)

    def cut(self, target, cutters):
        """Boolean difference; cutters are removed from the part list."""
        lib.activate(target)
        for c in cutters:
            if c in self.parts:
                self.parts.remove(c)
            m = target.modifiers.new("cut", 'BOOLEAN')
            m.operation = 'DIFFERENCE'
            m.solver = 'EXACT'
            m.object = c
            lib.apply_modifiers(target)
            bpy.data.objects.remove(c, do_unlink=True)
        lib.activate(target)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))


# ---------------------------------------------------------------- arms

def right_hand(k, top, bottom, trigger, forearm=(0.13, -0.34, -0.17), side=1, node="ArmR"):
    """Gloved right hand wrapped around a pistol grip running from `top` to
    `bottom` (gun-space (y, z) of the grip's centre line), index on `trigger`."""
    T = Vector((0.0, top[0], top[1]))
    B = Vector((0.0, bottom[0], bottom[1]))
    axis = (B - T).normalized()                    # down the grip
    fwd = Vector((0, axis.z * -1, axis.y)) if axis.z < 0 else Vector((0, 1, 0))
    fwd = Vector((0, -axis.z, axis.y)).normalized()  # perpendicular, towards the front strap
    if fwd.y < 0:
        fwd = -fwd
    mid = T + (B - T) * 0.48
    # palm and back of hand on the right side / back strap
    palm = mid - fwd * 0.012 + Vector((0.016 * side, 0, 0))
    k.box(node, GLOVE, palm, (0.034, 0.05, 0.085), 0.012, rot=(math.degrees(math.atan2(axis.y, -axis.z)), 0, 0))
    # three fingers wrapping the front strap from right to left
    for t in (0.42, 0.62, 0.82):
        c = T + (B - T) * t + fwd * 0.02
        k.cyl(node, GLOVE, c + Vector((0.03 * side, -0.006, 0)), c + Vector((-0.022 * side, 0.0, 0)), 0.0112, 10, 0.002)
        k.sphere(node, GLOVE, c + Vector((-0.024 * side, -0.008, 0)), 0.0105)
    # index finger along the guard onto the trigger (or wrapped, for a foregrip)
    if trigger is None:
        trigger = (T + (B - T) * 0.22 + fwd * 0.02).yz
    tr = Vector((0.0, trigger[0], trigger[1]))
    base = T + (B - T) * 0.2 + fwd * 0.012 + Vector((0.02 * side, 0, 0))
    k.cyl(node, GLOVE, base, tr + Vector((0.012 * side, -0.006, 0.0)), 0.0095, 10, 0.002)
    k.cyl(node, GLOVE, tr + Vector((0.012 * side, -0.008, 0.0)), tr + Vector((0.004 * side, 0.004, -0.008)), 0.0085, 10, 0.002)
    # thumb over the left side, pointing forward
    th = T + (B - T) * 0.1 + Vector((-0.022 * side, 0, 0.006))
    k.cyl(node, GLOVE, th - fwd * 0.02, th + fwd * 0.03 + Vector((0, 0, 0.006)), 0.0105, 10, 0.002)
    # wrist, forearm, sleeve
    w = B - fwd * 0.015 + Vector((0.016 * side, 0, 0.012))
    e = w + Vector(forearm)
    k.cyl(node, GLOVE, w, w + (e - w) * 0.17, 0.03, 14, 0.002, r2=0.034)
    k.cyl(node, SLEEVE, w + (e - w) * 0.15, e, 0.044, 14, 0.003, r2=0.056)
    k.cyl(node, SLEEVE, w + (e - w) * 0.13, w + (e - w) * 0.2, 0.048, 14, 0.003)


def left_hand(k, palm, forearm_dir=(-0.26, -0.3, -0.3), watch=True, under=True):
    """Gloved support hand cupping a handguard/pump at `palm`."""
    p = Vector(palm)
    k.box("ArmL", GLOVE, (p.x - 0.004, p.y, p.z - 0.008), (0.05, 0.075, 0.028), 0.01)
    for i, dy in enumerate((-0.024, -0.008, 0.008, 0.024)):  # fingers wrap over the left side
        a = (p.x - 0.03, p.y + dy, p.z - 0.008)
        b = (p.x - 0.026, p.y + dy + 0.004, p.z + 0.04)
        k.cyl("ArmL", GLOVE, a, b, 0.0098, 10, 0.002)
    k.cyl("ArmL", GLOVE, (p.x + 0.02, p.y - 0.03, p.z - 0.02), (p.x + 0.03, p.y + 0.01, p.z + 0.008), 0.0105, 10, 0.002)
    w = p + Vector((-0.01, -0.05, -0.03))
    e = w + Vector(forearm_dir)
    k.cyl("ArmL", GLOVE, w, w + (e - w) * 0.16, 0.03, 14, 0.002, r2=0.033)
    k.cyl("ArmL", SLEEVE, w + (e - w) * 0.14, e, 0.044, 14, 0.003, r2=0.054)
    if watch:
        c = w + (e - w) * 0.1
        k.cyl("ArmL", POLY, c - (e - w).normalized() * 0.008, c + (e - w).normalized() * 0.008, 0.035, 16, 0.002)
        k.cyl("ArmL", METAL, c + Vector((0, 0, 0.033)), c + Vector((0, 0, 0.04)), 0.014, 16, 0.001)


# ---------------------------------------------------------------- weapons (gun space)

def rifle(k):
    """AR-7 Carbine: original pattern carbine with FDE furniture and a reflex sight."""
    k.prism("Weapon", METAL, [(-0.07, 0.0), (0.12, 0.0), (0.135, 0.02), (0.135, 0.046), (-0.08, 0.046), (-0.085, 0.02)], 0.032)  # lower
    upper = k.prism("Weapon", METAL, [(-0.075, 0.046), (0.165, 0.046), (0.165, 0.088), (-0.075, 0.088)], 0.034, bevel=0.0025)
    port = k.box("cut", METAL, (0.017, 0.03, 0.066), (0.006, 0.06, 0.018), 0)
    k.cut(upper, [port])
    k.box("Weapon", METAL, (0.0175, 0.03, 0.066), (0.002, 0.055, 0.016), 0.0005)  # dust cover
    k.box("Weapon", METAL, (0, 0.13, 0.095), (0.022, 0.43, 0.012), 0.001)  # top rail
    for i in range(30):
        k.box("Weapon", METAL, (0, -0.06 + i * 0.0135, 0.1025), (0.024, 0.0065, 0.004), 0.0004)
    hg = k.cyl("Weapon", ACCENT, (0, 0.165, 0.066), (0, 0.43, 0.066), 0.026, 8, 0.002)
    cutters = []
    for i in range(6):
        for side in (-1, 1):
            cutters.append(k.box("cut", METAL, (side * 0.025, 0.2 + i * 0.038, 0.066), (0.02, 0.02, 0.008), 0))
    k.cut(hg, cutters)
    k.cyl("Weapon", METAL, (0, 0.43, 0.066), (0, 0.6, 0.066), 0.0085, 12)  # barrel
    brake = k.cyl("Weapon", METAL, (0, 0.6, 0.066), (0, 0.655, 0.066), 0.0125, 12, 0.0015)
    k.cut(brake, [k.box("cut", METAL, (0, 0.62 + i * 0.012, 0.074), (0.03, 0.005, 0.008), 0) for i in range(3)])
    k.box("Weapon", METAL, (0, 0.45, 0.08), (0.024, 0.022, 0.03), 0.002)  # gas block
    k.prism("Weapon", METAL, [(0.44, 0.09), (0.46, 0.09), (0.455, 0.135), (0.445, 0.135)], 0.006, bevel=0.0008)  # front post
    # magazine (curved), grip, trigger, guard
    k.prism("Mag", METAL, [(0.07, 0.002), (0.128, 0.002), (0.152, -0.09), (0.168, -0.185), (0.108, -0.192), (0.094, -0.09)], 0.026, bevel=0.002)
    k.prism("Mag", POLY, [(0.105, -0.192), (0.172, -0.186), (0.174, -0.2), (0.104, -0.205)], 0.03, bevel=0.002)
    k.prism("Weapon", POLY, [(-0.035, 0.002), (0.005, 0.002), (-0.018, -0.105), (-0.058, -0.1)], 0.031, bevel=0.004)  # pistol grip
    k.box("Weapon", METAL, (0, 0.04, -0.03), (0.024, 0.075, 0.005), 0.001)  # trigger guard
    k.box("Weapon", METAL, (0, 0.076, -0.015), (0.008, 0.006, 0.03), 0.001)
    k.prism("Weapon", METAL, [(0.03, -0.002), (0.038, -0.002), (0.036, -0.022), (0.03, -0.026)], 0.005, bevel=0.0006)  # trigger
    # stock
    k.cyl("Weapon", METAL, (0, -0.075, 0.062), (0, -0.27, 0.062), 0.016, 14)
    k.prism("Weapon", ACCENT, [(-0.16, 0.088), (-0.3, 0.094), (-0.315, 0.06), (-0.31, -0.035), (-0.255, -0.035), (-0.2, 0.036), (-0.16, 0.042)], 0.042, bevel=0.004)
    k.box("Weapon", POLY, (0, -0.318, 0.03), (0.044, 0.014, 0.13), 0.003)  # butt pad
    k.box("Slide", METAL, (0, -0.088, 0.08), (0.04, 0.02, 0.008), 0.001)  # charging handle
    # reflex sight
    k.box("Weapon", METAL, (0, 0.04, 0.107), (0.026, 0.06, 0.012), 0.0015)
    hood = k.cyl("Weapon", POLY, (0, 0.015, 0.13), (0, 0.07, 0.13), 0.022, 20, 0.002)
    k.cut(hood, [k.cyl("cut", POLY, (0, 0.01, 0.13), (0, 0.075, 0.13), 0.017, 20, 0)])
    k.cyl("Weapon", LENS, (0, 0.062, 0.13), (0, 0.064, 0.13), 0.0172, 20, 0)
    k.sphere("Weapon", EMIT, (0, 0.063, 0.131), 0.0016)
    # receiver details: magwell flare, pins, bolt catch, forward assist, selector
    k.prism("Weapon", METAL, [(0.06, -0.004), (0.138, -0.004), (0.142, 0.012), (0.056, 0.012)], 0.036, bevel=0.002)
    for yy, zz in ((-0.055, 0.03), (0.105, 0.03)):
        k.cyl("Weapon", METAL, (-0.018, yy, zz), (0.018, yy, zz), 0.0045, 10, 0.0008)
    k.box("Weapon", METAL, (-0.018, 0.075, 0.022), (0.004, 0.022, 0.012), 0.0008)
    k.cyl("Weapon", METAL, (0.012, -0.02, 0.074), (0.024, -0.035, 0.074), 0.006, 10, 0.001)
    k.cyl("Weapon", METAL, (-0.018, -0.03, 0.03), (-0.021, -0.03, 0.03), 0.008, 12, 0.0008)
    k.box("Weapon", METAL, (-0.021, -0.03, 0.036), (0.002, 0.004, 0.012), 0.0004)
    right_hand(k, top=(-0.015, 0.0), bottom=(-0.039, -0.1), trigger=(0.034, -0.014))
    left_hand(k, palm=(0.0, 0.31, 0.03))
    return {"muzzle": (0, 0.66, 0.066), "mag_out": (0.0, 0.02, -0.32), "place": ((0.118, 0.26, -0.138), (1.5, 3.0, 7.0)),
            "kick": 1.0}


def pistol_support(k, grip_mid, forearm=(-0.2, -0.33, -0.22)):
    """Left hand cupping the right fist on a pistol (two-handed hold)."""
    m = Vector(grip_mid)
    k.box("ArmL", GLOVE, m + Vector((-0.036, -0.004, -0.004)), (0.026, 0.06, 0.08), 0.01, rot=(-14, 0, 0))
    for dz in (-0.02, -0.045, -0.07):
        c = m + Vector((0, 0.036, dz))
        k.cyl("ArmL", GLOVE, c + Vector((-0.04, -0.01, 0)), c + Vector((0.028, 0.004, 0)), 0.0105, 10, 0.002)
    k.cyl("ArmL", GLOVE, m + Vector((-0.03, 0.0, 0.035)), m + Vector((-0.024, 0.06, 0.042)), 0.0102, 10, 0.002)  # thumb fwd
    w = m + Vector((-0.04, -0.02, -0.05))
    e = w + Vector(forearm)
    k.cyl("ArmL", GLOVE, w, w + (e - w) * 0.17, 0.03, 14, 0.002, r2=0.033)
    k.cyl("ArmL", SLEEVE, w + (e - w) * 0.15, e, 0.044, 14, 0.003, r2=0.054)
    c = w + (e - w) * 0.1
    k.cyl("ArmL", POLY, c - (e - w).normalized() * 0.008, c + (e - w).normalized() * 0.008, 0.035, 16, 0.002)


def pistol(k):
    """P9 Sidearm: polymer-frame service pistol with steel slide."""
    slide = k.prism("Slide", METAL, [(-0.062, 0.03), (0.128, 0.03), (0.13, 0.058), (0.122, 0.064), (-0.056, 0.064), (-0.064, 0.056)], 0.03, bevel=0.0022)
    cuts = [k.box("cut", METAL, (side * 0.016, -0.05 + i * 0.006, 0.048), (0.006, 0.0025, 0.026), 0) for side in (-1, 1) for i in range(6)]
    cuts.append(k.box("cut", METAL, (0.01, 0.03, 0.064), (0.014, 0.04, 0.012), 0))  # ejection port
    k.cut(slide, cuts)
    k.box("Slide", METAL, (0.0055, 0.03, 0.06), (0.012, 0.036, 0.006), 0.0006)                   # barrel hood in port
    k.cyl("Slide", METAL, (0, 0.126, 0.045), (0, 0.133, 0.045), 0.0062, 12, 0.0006)              # barrel crown
    k.box("Slide", METAL, (0, -0.05, 0.068), (0.022, 0.012, 0.01), 0.001)                        # rear sight
    k.sphere("Slide", EMIT, (0.006, -0.0535, 0.07), 0.0012)
    k.sphere("Slide", EMIT, (-0.006, -0.0535, 0.07), 0.0012)
    k.box("Slide", METAL, (0, 0.115, 0.068), (0.005, 0.008, 0.01), 0.0008)                       # front sight
    k.sphere("Slide", EMIT, (0, 0.111, 0.071), 0.0013)
    k.prism("Weapon", POLY, [(-0.055, 0.0), (0.118, 0.0), (0.124, 0.03), (-0.055, 0.03)], 0.027, bevel=0.002)    # frame
    for i in range(4):
        k.box("Weapon", POLY, (0, 0.07 + i * 0.012, -0.002), (0.022, 0.006, 0.004), 0.0005)    # accessory rail
    k.prism("Weapon", POLY, [(-0.05, 0.002), (0.0, 0.002), (-0.02, -0.1), (-0.062, -0.094)], 0.03, bevel=0.004)   # grip
    k.prism("Weapon", POLY, [(-0.052, 0.0), (-0.042, 0.0), (-0.068, -0.012), (-0.072, -0.004)], 0.026, bevel=0.002)  # beavertail
    k.box("Weapon", POLY, (0, 0.034, -0.026), (0.022, 0.062, 0.006), 0.0015)                     # trigger guard
    k.box("Weapon", POLY, (0, 0.064, -0.012), (0.022, 0.006, 0.026), 0.0015)
    k.prism("Weapon", METAL, [(0.022, -0.002), (0.03, -0.002), (0.028, -0.02), (0.022, -0.024)], 0.005, bevel=0.0006)
    k.prism("Mag", METAL, [(-0.045, -0.004), (-0.012, -0.004), (-0.03, -0.092), (-0.058, -0.092)], 0.022, bevel=0.0015)
    k.prism("Mag", POLY, [(-0.062, -0.093), (-0.017, -0.093), (-0.018, -0.104), (-0.064, -0.103)], 0.032, bevel=0.002)
    right_hand(k, top=(-0.022, 0.0), bottom=(-0.044, -0.098), trigger=(0.025, -0.012), forearm=(0.12, -0.33, -0.2))
    pistol_support(k, (0.0, -0.03, -0.045))
    return {"muzzle": (0, 0.135, 0.045), "mag_out": (0.0, -0.02, -0.26), "place": ((0.105, 0.24, -0.105), (2.0, 1.0, 6.0)),
            "slide_fire": -0.032, "kick": 1.4}


def shotgun(k):
    """KS-12 Breacher: pump-action shotgun with side-saddle shells."""
    k.prism("Weapon", METAL, [(-0.085, 0.0), (0.125, 0.0), (0.125, 0.064), (-0.09, 0.064), (-0.095, 0.03)], 0.036, bevel=0.0025)
    k.box("Weapon", METAL, (0.0185, 0.03, 0.04), (0.002, 0.05, 0.016), 0.0004)                  # ejection port cover
    k.cyl("Weapon", METAL, (0, 0.12, 0.05), (0, 0.6, 0.05), 0.0115, 16, 0.001)                  # barrel
    k.cyl("Weapon", METAL, (0, 0.12, 0.02), (0, 0.53, 0.02), 0.0135, 16, 0.001)                 # magazine tube
    k.cyl("Weapon", METAL, (0, 0.53, 0.02), (0, 0.545, 0.02), 0.015, 16, 0.001)                 # cap
    k.box("Weapon", METAL, (0, 0.5, 0.035), (0.014, 0.018, 0.03), 0.001)                        # barrel clamp
    k.sphere("Weapon", BRASS, (0, 0.59, 0.065), 0.003)                                         # bead sight
    pump = k.cyl("Slide", POLY, (0, 0.2, 0.024), (0, 0.36, 0.024), 0.024, 16, 0.002)
    k.cut(pump, [k.cyl("cut", POLY, (0, 0.21 + i * 0.016, 0.024), (0, 0.216 + i * 0.016, 0.024), 0.03, 16, 0) for i in range(9)])
    k.cyl("Slide", POLY, (0, 0.2, 0.024), (0, 0.36, 0.024), 0.0205, 16, 0.001)                  # pump core under grooves
    for i in range(4):                                                                         # side saddle shells
        y = -0.03 + i * 0.022
        k.cyl("Weapon", POLY, (-0.019, y, 0.032), (-0.025, y, 0.032), 0.0092, 12, 0.0006)
        k.cyl("Weapon", BRASS, (-0.025, y, 0.032), (-0.029, y, 0.032), 0.0095, 12, 0.0006)
    k.box("Weapon", POLY, (-0.0205, 0.004, 0.032), (0.004, 0.1, 0.03), 0.0015)
    k.prism("Weapon", POLY, [(-0.035, 0.002), (0.005, 0.002), (-0.018, -0.105), (-0.058, -0.1)], 0.031, bevel=0.004)
    k.box("Weapon", METAL, (0, 0.04, -0.03), (0.024, 0.075, 0.005), 0.001)
    k.box("Weapon", METAL, (0, 0.076, -0.015), (0.008, 0.006, 0.03), 0.001)
    k.prism("Weapon", METAL, [(0.03, -0.002), (0.038, -0.002), (0.036, -0.022), (0.03, -0.026)], 0.005, bevel=0.0006)
    k.prism("Weapon", ACCENT, [(-0.09, 0.06), (-0.33, 0.072), (-0.345, 0.05), (-0.34, -0.045), (-0.28, -0.045), (-0.13, 0.016), (-0.09, 0.016)], 0.04, bevel=0.004)
    k.box("Weapon", POLY, (0, -0.348, 0.013), (0.042, 0.014, 0.12), 0.003)
    k.prism("Mag", POLY, [(0.0, 0.0), (0.06, 0.0), (0.06, 0.017), (0.0, 0.017)], 0.017, x=-0.12, bevel=0.002)  # shell in hand
    right_hand(k, top=(-0.015, 0.0), bottom=(-0.039, -0.1), trigger=(0.034, -0.014))
    left_hand(k, palm=(0.0, 0.28, 0.0), forearm_dir=(-0.26, -0.3, -0.32))
    return {"muzzle": (0, 0.61, 0.05), "mag_out": (0.0, 0.0, 0.0), "place": ((0.118, 0.265, -0.135), (1.5, 3.0, 7.0)),
            "pump": True, "kick": 2.2}


def smg(k):
    """VX-9 Ripper: compact polymer SMG with integral suppressor and foregrip."""
    k.prism("Weapon", POLY, [(-0.065, 0.0), (0.14, 0.0), (0.16, 0.02), (0.16, 0.072), (-0.065, 0.072), (-0.07, 0.04)], 0.036, bevel=0.003)
    k.box("Weapon", METAL, (0, 0.05, 0.078), (0.022, 0.22, 0.01), 0.001)
    for i in range(16):
        k.box("Weapon", METAL, (0, -0.05 + i * 0.0135, 0.0845), (0.024, 0.0065, 0.004), 0.0004)
    sup = k.cyl("Weapon", METAL, (0, 0.16, 0.045), (0, 0.34, 0.045), 0.02, 18, 0.002)
    k.cut(sup, [k.cyl("cut", METAL, (0, 0.18 + i * 0.03, 0.045), (0, 0.186 + i * 0.03, 0.045), 0.03, 18, 0) for i in range(5)])
    k.cyl("Weapon", METAL, (0, 0.18, 0.045), (0, 0.33, 0.045), 0.0175, 18, 0.001)
    k.cyl("Weapon", POLY, (0, 0.11, 0.0), (0, 0.118, -0.075), 0.013, 14, 0.002)                  # vertical grip
    k.prism("Mag", METAL, [(0.04, 0.0), (0.068, 0.0), (0.074, -0.15), (0.046, -0.15)], 0.022, bevel=0.0018)
    k.prism("Mag", POLY, [(0.042, -0.15), (0.078, -0.15), (0.078, -0.162), (0.04, -0.162)], 0.026, bevel=0.002)
    k.prism("Weapon", POLY, [(-0.035, 0.002), (0.005, 0.002), (-0.018, -0.1), (-0.056, -0.096)], 0.03, bevel=0.004)
    k.box("Weapon", POLY, (0, 0.012, -0.026), (0.022, 0.06, 0.005), 0.0012)
    k.prism("Weapon", METAL, [(0.016, -0.002), (0.024, -0.002), (0.022, -0.02), (0.016, -0.024)], 0.005, bevel=0.0006)
    for sx in (-1, 1):                                                                        # wire stock
        k.cyl("Weapon", METAL, (sx * 0.014, -0.065, 0.05), (sx * 0.014, -0.25, 0.04), 0.005, 8, 0.0006)
    k.box("Weapon", POLY, (0, -0.255, 0.02), (0.04, 0.012, 0.09), 0.002)
    k.cyl("Slide", METAL, (-0.018, 0.09, 0.058), (-0.034, 0.09, 0.058), 0.005, 10, 0.0008)        # cocking knob
    k.box("Weapon", POLY, (0, 0.0, 0.094), (0.024, 0.04, 0.01), 0.0015)                          # mini reflex sight
    k.box("Weapon", POLY, (0, 0.012, 0.112), (0.026, 0.006, 0.028), 0.0015)
    k.sphere("Weapon", EMIT, (0, 0.0145, 0.112), 0.0014)
    right_hand(k, top=(-0.015, 0.0), bottom=(-0.037, -0.098), trigger=(0.02, -0.013))
    right_hand(k, top=(0.11, 0.0), bottom=(0.118, -0.07), trigger=None, forearm=(-0.22, -0.3, -0.24), side=-1, node="ArmL")
    return {"muzzle": (0, 0.345, 0.045), "mag_out": (0.0, 0.02, -0.3), "place": ((0.112, 0.25, -0.13), (1.5, 3.0, 6.5)),
            "kick": 0.8}


WEAPONS = {"rifle": rifle, "pistol": pistol, "shotgun": shotgun, "smg": smg}


# ---------------------------------------------------------------- texturing

def paint(P, part, edges, seed):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    n1 = pt.fbm(P, 30, 4, seed)
    n2 = pt.fbm(P, 90, 3, seed + 5)
    scratch = pt.smooth(0.01, 0.0, np.abs(pt.fbm(P * np.array([1, 0.2, 1], np.float32), 60, 3, seed + 9) - 0.5))
    wear = np.clip(edges * 1.4, 0, 1)
    rough = np.full(len(P), 0.6, np.float32)
    metal = np.zeros(len(P), np.float32)
    col = np.zeros((len(P), 3), np.float32)
    # parkerized gunmetal: dark, slightly blue, edges worn to bright steel
    gm = pt.lerp(pt.hexc("#24272b"), pt.hexc("#16181b"), n1)
    gm = pt.lerp(gm, pt.hexc("#8d939a"), np.clip(wear * 0.7 + scratch * 0.35, 0, 1))
    m = part == METAL
    col[m] = gm[m]
    rough[m] = (0.42 - wear[m] * 0.2 + n2[m] * 0.1)
    metal[m] = 0.85
    pl = pt.lerp(pt.hexc("#202122"), pt.hexc("#131414"), n1) * (0.92 + 0.08 * n2)[:, None]   # stippled polymer
    pl = pt.lerp(pl, pt.hexc("#4a4c4e"), wear * 0.35)
    m = part == POLY
    col[m] = pl[m]
    rough[m] = 0.78
    fde = pt.lerp(pt.hexc("#8b7a5c"), pt.hexc("#6c5d45"), n1)                                  # flat dark earth
    fde = pt.lerp(fde, pt.hexc("#b5a585"), wear * 0.45)
    fde = pt.lerp(fde, pt.hexc("#3b3326"), pt.smooth(0.6, 0.85, pt.fbm(P, 12, 3, seed + 2)) * 0.4)
    m = part == ACCENT
    col[m] = fde[m]
    rough[m] = 0.7
    glove = pt.lerp(pt.hexc("#26282a"), pt.hexc("#121313"), n1)
    knuckle = pt.smooth(0.55, 0.7, pt.vnoise(P, 140, seed + 4))
    glove = pt.lerp(glove, pt.hexc("#3a3c3e"), knuckle * 0.4 + wear * 0.3)
    m = part == GLOVE
    col[m] = glove[m]
    rough[m] = 0.85
    camo = pt.fbm(P, 18, 4, seed + 11)
    sleeve = np.where((camo > 0.55)[:, None], pt.hexc("#4d4a37"), np.where((camo > 0.45)[:, None], pt.hexc("#5f5b45"), pt.hexc("#3b3a2c")))
    sleeve = sleeve * (0.9 + 0.1 * np.sin(P[:, 1] * 1600) * np.sin(P[:, 0] * 1600))[:, None]
    m = part == SLEEVE
    col[m] = sleeve[m]
    rough[m] = 0.92
    col[part == BRASS] = pt.hexc("#b08d3c")
    rough[part == BRASS] = 0.35
    metal[part == BRASS] = 1.0
    col[part == LENS] = pt.hexc("#0f1a1a")
    rough[part == LENS] = 0.08
    col[part == EMIT] = pt.hexc("#ff2a1a")
    return np.clip(col, 0, 1), rough, metal


def texture(ob, wid):
    lib.activate(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(50), island_margin=0.004)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003, shape_method='CONCAVE')
    bpy.ops.object.mode_set(mode='OBJECT')
    edges = lib.bake_pointiness(ob, TEX)
    ao = lib.bake_ao(ob, TEX)
    pos, nor, part, valid = pt.rasterize(ob, TEX)
    rgb = np.zeros((TEX, TEX, 3), np.float32)
    orm = np.zeros((TEX, TEX, 3), np.float32)
    c, r, m = paint(pos[valid], part[valid], edges[valid], 17)
    rgb[valid] = c * (0.35 + 0.65 * ao[valid])[:, None]
    orm[valid] = np.stack([ao[valid], r, m], 1)
    alb = pt.to_image(bpy, "vm_%s_albedo" % wid, rgb, valid)
    ormi = pt.to_image(bpy, "vm_%s_orm" % wid, orm, valid)
    mat = lib.pbr_material("vm_" + wid, alb, ormi)
    emit = lib.flat_material("sight_dot", "#ff2a1a", emission="#ff2a1a", strength=12.0)
    lens = lib.flat_material("lens", "#0f1a1a", roughness=0.05)
    lens.blend_method = 'BLEND' if hasattr(lens, "blend_method") else None
    for i in range(len(ob.data.materials)):
        ob.data.materials[i] = emit if i == EMIT else mat


# ---------------------------------------------------------------- animation (node TRS)

def key(ob, frame, loc=None, rot=None):
    if loc is not None:
        ob.location = loc
        ob.keyframe_insert("location", frame=frame)
    if rot is not None:
        ob.rotation_euler = [math.radians(v) for v in rot]
        ob.keyframe_insert("rotation_euler", frame=frame)


def animate(nodes, info):
    root, mag, slide, arm_l = nodes["Root"], nodes.get("Mag"), nodes.get("Slide"), nodes.get("ArmL")
    base_loc = Vector(info["place"][0])
    base_rot = Vector(info["place"][1])
    tracks = {}

    def action(ob, name):
        act = bpy.data.actions.new("%s_%s" % (ob.name, name))
        act.use_fake_user = True
        if ob.animation_data is None:
            ob.animation_data_create()
        ob.animation_data.action = act
        tracks.setdefault(ob.name, {})[name] = act
        return act

    def rest(ob):
        return (Vector(ob.location), Vector([math.degrees(a) for a in ob.rotation_euler]))

    rests = {n: rest(o) for n, o in nodes.items() if o is not None}
    # idle: slow breathing sway
    action(root, "idle")
    for f, d in ((0, 0), (30, 1), (60, 0)):
        key(root, f, base_loc + Vector((0, 0, -0.003 * d)), base_rot + Vector((0.6 * d, 0, 0.3 * d)))
    # fire: kick back and up
    kick = info.get("kick", 1.0)
    pump = info.get("pump", False)
    fire_len = 22 if pump else 6
    action(root, "fire")
    key(root, 0, base_loc, base_rot)
    key(root, 1, base_loc + Vector((0.004, -0.028, 0.006)) * kick, base_rot + Vector((4.0, 0, -1.0)) * kick)
    key(root, 6, base_loc, base_rot)
    if pump:
        key(root, 12, base_loc + Vector((0, -0.01, -0.005)), base_rot + Vector((-2, 4, 0)))
        key(root, fire_len, base_loc, base_rot)
    if slide:
        action(slide, "fire")
        l0, r0 = rests["Slide"]
        key(slide, 0, l0, r0)
        if pump:
            key(slide, 8, l0, r0)
            key(slide, 12, l0 + Vector((0, -0.075, 0)), r0)
            key(slide, 17, l0, r0)
        elif "slide_fire" in info:
            key(slide, 1, l0 + Vector((0, info["slide_fire"], 0)), r0)
            key(slide, 4, l0, r0)
        key(slide, fire_len, l0, r0)
    if pump and arm_l:
        action(arm_l, "fire")
        l0, r0 = rests["ArmL"]
        key(arm_l, 0, l0, r0)
        key(arm_l, 8, l0, r0)
        key(arm_l, 12, l0 + Vector((0, -0.075, 0)), r0)
        key(arm_l, 17, l0, r0)
        key(arm_l, fire_len, l0, r0)
    # reload (60 frames, the game rescales to reloadSec)
    action(root, "reload")
    key(root, 0, base_loc, base_rot)
    key(root, 10, base_loc + Vector((-0.02, -0.02, -0.03)), base_rot + Vector((-8, 22, 6)))
    key(root, 50, base_loc + Vector((-0.02, -0.02, -0.03)), base_rot + Vector((-8, 22, 6)))
    key(root, 60, base_loc, base_rot)
    if pump:
        mag = None  # shotgun: the "Mag" node is a shell carried by the left hand
        shell = nodes.get("Mag")
        if shell and arm_l:
            action(shell, "reload")
            action(arm_l, "reload")
            ls, rs = rests["Mag"]
            la, ra = rests["ArmL"]
            port = Vector((0.12, -0.24, -0.02))          # from the hand's rest to the loading port
            low = Vector((0.05, -0.35, -0.22))
            f = 0
            key(shell, f, ls + Vector((0, 0, -0.5)), rs)
            key(arm_l, f, la, ra)
            for i in range(3):
                f0 = 8 + i * 13
                key(arm_l, f0, la + low, ra)
                key(shell, f0, ls + low + Vector((0.0, 0.0, 0.0)), rs)
                key(arm_l, f0 + 6, la + port, ra + Vector((0, 0, 15)))
                key(shell, f0 + 6, ls + port + Vector((0.12, 0.02, 0.0)), rs)
                key(shell, f0 + 7, ls + Vector((0, 0, -0.5)), rs)
            key(arm_l, 52, la + low, ra)
            key(arm_l, 58, la, ra)
            key(arm_l, 60, la, ra)
            key(shell, 60, ls + Vector((0, 0, -0.5)), rs)
    if mag:
        action(mag, "reload")
        l0, r0 = rests["Mag"]
        out = l0 + Vector(info["mag_out"])
        key(mag, 0, l0, r0)
        key(mag, 12, l0, r0)
        key(mag, 22, out, r0 + Vector((-25, 0, 0)))
        key(mag, 34, out + Vector((0, 0, -0.2)), r0)
        key(mag, 40, out, r0 + Vector((-15, 0, 0)))
        key(mag, 47, l0 + Vector((0, 0, -0.02)), r0)
        key(mag, 50, l0, r0)
        key(mag, 60, l0, r0)
    if arm_l and not pump:
        action(arm_l, "reload")
        l0, r0 = rests["ArmL"]
        to_mag = l0 + Vector((0.01, -0.17, -0.2))
        key(arm_l, 0, l0, r0)
        key(arm_l, 8, l0, r0)
        key(arm_l, 16, to_mag, r0 + Vector((10, 0, 0)))
        key(arm_l, 30, to_mag + Vector((0, -0.05, -0.25)), r0)
        key(arm_l, 42, to_mag + Vector((0, 0, -0.03)), r0)
        key(arm_l, 50, to_mag + Vector((0, 0, 0.02)), r0 + Vector((-6, 0, 0)))
        key(arm_l, 58, l0, r0)
        key(arm_l, 60, l0, r0)
    if slide:
        action(slide, "reload")
        l0, r0 = rests["Slide"]
        key(slide, 0, l0, r0)
        key(slide, 50, l0, r0)
        key(slide, 53, l0 + Vector((0, -0.045, 0)), r0)
        key(slide, 56, l0, r0)
        key(slide, 60, l0, r0)
    # draw: swing up from below
    action(root, "draw")
    key(root, 0, base_loc + Vector((0.03, -0.05, -0.18)), base_rot + Vector((-45, 0, -10)))
    key(root, 12, base_loc, base_rot)
    for name, acts in tracks.items():
        lib.push_object_actions(nodes[name], acts)


# ---------------------------------------------------------------- assemble / export

def build(wid):
    lib.reset()
    bpy.context.scene.render.fps = 30
    k = Kit()
    info = WEAPONS[wid](k)
    ob = lib.join(k.parts, "vm")
    texture(ob, wid)
    nodes = lib.separate_by_groups(ob, ["Mag", "Slide", "ArmR", "ArmL"])
    ob.name = "Weapon"
    nodes["Weapon"] = ob
    for o in nodes.values():
        for g in list(o.vertex_groups):
            o.vertex_groups.remove(g)
    root = lib.link(bpy.data.objects.new("Root", None))
    muzzle = lib.link(bpy.data.objects.new("Muzzle", None))
    muzzle.location = info["muzzle"]
    for o in list(nodes.values()) + [muzzle]:
        o.parent = root
    root.location = info["place"][0]
    root.rotation_euler = [math.radians(v) for v in info["place"][1]]
    nodes["Root"] = root
    animate(nodes, info)
    tris = sum(lib.tri_count(o) for o in nodes.values() if o.type == 'MESH')
    print("%s: %d triangles" % (wid, tris))
    return nodes, root


def export(root, path):
    objs = [root] + list(root.children)
    lib.activate(root, *objs)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_animations=True, export_animation_mode='NLA_TRACKS',
                              export_image_format='JPEG', export_jpeg_quality=90)


def preview(root, d, wid):
    for o in [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT')]:
        bpy.data.objects.remove(o, do_unlink=True)
    lib.render_setup((1040, 480), samples=40)
    sc = bpy.context.scene
    cam = lib.link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.angle = math.radians(75)
    cam.data.clip_start = 0.01
    cam.rotation_euler = (math.radians(90), 0, 0)   # look along +Y
    sc.camera = cam
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 6.0   # soft fill, like ambient in game
    lib.add_light('AREA', (0.5, 0.0, 0.7), 40, (1.0, 0.86, 0.72), size=0.8)
    lib.add_light('POINT', (-0.5, 0.8, 0.3), 12, (0.6, 0.7, 1.0))
    lib.render(os.path.join(d, "vm_%s_fp.png" % wid))
    for o in [root] + list(root.children):
        if o.animation_data and o.animation_data.nla_tracks.get("reload"):
            o.animation_data.action = o.animation_data.nla_tracks["reload"].strips[0].action
    sc.frame_set(24)
    lib.render(os.path.join(d, "vm_%s_reload.png" % wid))
    for o in [root] + list(root.children):
        if o.animation_data:
            o.animation_data.action = None
    sc.frame_set(0)
    # studio beauty shot from the side
    cam.location = (0.95, root.location.y + 0.12, root.location.z + 0.1)
    lib.look_at(cam, root.location + Vector((0, 0.15, 0.0)))
    cam.data.angle = math.radians(45)
    lib.add_light('AREA', (0.8, root.location.y + 0.6, 0.6), 120, (1, 1, 1), size=1.2)
    lib.render(os.path.join(d, "vm_%s_side.png" % wid))


def main():
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    pdir = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    os.makedirs(OUT_DIR, exist_ok=True)
    for wid in WEAPONS:
        if only and wid != only:
            continue
        nodes, root = build(wid)
        export(root, os.path.join(OUT_DIR, "vm_%s.glb" % wid))
        if pdir:
            os.makedirs(pdir, exist_ok=True)
            preview(root, pdir, wid)


if __name__ == "__main__":
    main()
