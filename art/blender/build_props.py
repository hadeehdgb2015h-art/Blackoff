"""Props for Blackoff. Currently: the supply cache (random weapon box).

Run:  /opt/blender-venv/bin/python art/blender/build_props.py [--preview DIR]
Output: client/assets/models/supply_box.glb
  - "Body": hollow armoured crate (front faces +Y here = -Z in Godot)
  - "Lid": hinged at its origin (back top edge); BoxView rotates it on X
  - "GlowAnchor": where the game places the interior light
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
import painter as pt  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "client", "assets", "models", "supply_box.glb")

W, D, H = 1.4, 0.7, 0.62     # crate size (x, y, z)
LID_H = 0.1
PANEL, FRAME, HAZARD, GLOW = range(4)


def box(name, center, size, part, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    lib.activate(ob)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        m = ob.modifiers.new("bev", 'BEVEL')
        m.width = bevel
        m.segments = 2
        lib.apply_modifiers(ob)
    tag(ob, part)
    return ob


def cyl(name, center, radius, depth, axis, part):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth, location=center, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    lib.activate(ob)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    tag(ob, part)
    return ob


MATS = {}


def tag(ob, part):
    ob.data.materials.clear()
    for k in range(4):
        ob.data.materials.append(MATS[k])
    for p in ob.data.polygons:
        p.material_index = part


def hollow_body():
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, H / 2))
    ob = bpy.context.active_object
    ob.name = "shell"
    ob.scale = (W, D, H)
    lib.activate(ob)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # remove the top face, then give the walls thickness
    top = max(ob.data.polygons, key=lambda p: p.center.z)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[top.index]], context='FACES_ONLY')
    bm.to_mesh(ob.data)
    bm.free()
    ob.modifiers.new("sol", 'SOLIDIFY').thickness = 0.04
    bev = ob.modifiers.new("bev", 'BEVEL')
    bev.width = 0.012
    bev.segments = 2
    lib.apply_modifiers(ob)
    tag(ob, PANEL)
    return ob


def build():
    lib.reset()
    MATS[PANEL] = lib.flat_material("panel", "#808080")
    MATS[FRAME] = lib.flat_material("frame", "#808080")
    MATS[HAZARD] = lib.flat_material("hazard", "#808080")
    MATS[GLOW] = lib.flat_material("glow", "#ff8a2a", emission="#ff7a1a", strength=6.0)
    parts = [hollow_body()]
    # steel frame: corner posts, top and bottom rails, two straps, skids
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(box("post", (sx * (W / 2 - 0.02), sy * (D / 2 - 0.02), H / 2), (0.07, 0.07, H + 0.02), FRAME, 0.008))
    for z in (0.03, H - 0.03):
        for sy in (-1, 1):
            parts.append(box("rail", (0, sy * (D / 2 + 0.005), z), (W + 0.02, 0.03, 0.05), FRAME, 0.006))
        for sx in (-1, 1):
            parts.append(box("rail", (sx * (W / 2 + 0.005), 0, z), (0.03, D + 0.02, 0.05), FRAME, 0.006))
    for x in (-0.38, 0.38):  # straps on the outside of the front and back walls only
        for sy in (-1, 1):
            parts.append(box("strap", (x, sy * (D / 2 + 0.008), H / 2), (0.06, 0.018, H - 0.06), FRAME, 0.004))
    for x in (-0.5, 0.5):
        parts.append(box("skid", (x, 0, -0.01), (0.12, D + 0.04, 0.04), FRAME, 0.006))
    for sx in (-1, 1):  # side handles
        parts.append(cyl("handle", (sx * (W / 2 + 0.05), 0, H * 0.62), 0.016, 0.3, "y", FRAME))
        for sy in (-1, 1):
            parts.append(box("bracket", (sx * (W / 2 + 0.03), sy * 0.15, H * 0.62), (0.05, 0.03, 0.05), FRAME))
    parts.append(box("hazard_band", (0, D / 2 + 0.012, H * 0.3), (W - 0.2, 0.012, 0.09), HAZARD))
    parts.append(box("inner_glow", (0, 0, 0.08), (W - 0.12, D - 0.12, 0.02), GLOW))
    body = lib.join(parts, "Body")

    lid_parts = [
        box("lid", (0, D / 2 + 0.01, LID_H / 2), (W + 0.04, D + 0.04, LID_H), PANEL, 0.012),
        box("lid_rail_f", (0, D + 0.03, LID_H / 2), (W + 0.06, 0.03, LID_H + 0.01), FRAME, 0.006),
        box("lid_rail_b", (0, -0.01, LID_H / 2), (W + 0.06, 0.03, LID_H + 0.01), FRAME, 0.006),
        box("lid_hazard", (0, D / 2 + 0.01, LID_H + 0.003), (W - 0.3, 0.16, 0.006), HAZARD),
        box("lid_seam", (0, D + 0.02, 0.008), (W - 0.1, 0.02, 0.012), GLOW),
    ]
    for x in (-0.38, 0.38):
        lid_parts.append(box("lid_strap", (x, D / 2 + 0.01, LID_H / 2 + 0.005), (0.06, D + 0.06, LID_H + 0.012), FRAME, 0.005))
    for sx in (-1, 1):
        lid_parts.append(cyl("hinge", (sx * 0.45, -0.02, 0.0), 0.022, 0.16, "x", FRAME))
    lid = lib.join(lid_parts, "Lid")
    lid.location = (0, -D / 2, H)          # origin = hinge on the back top edge
    anchor = lib.link(bpy.data.objects.new("GlowAnchor", None))
    anchor.location = (0, 0, 0.45)
    return body, lid, anchor


def paint(P, part, seed):
    N = len(P)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    grime = pt.fbm(P, 6, 4, seed)
    scratches = pt.smooth(0.012, 0.0, np.abs(pt.fbm(P * np.array([1, 1, 6], np.float32), 14, 3, seed + 3) - 0.5))
    panel = pt.lerp(pt.hexc("#4c5537"), pt.hexc("#2c3221"), grime)               # olive drab paint
    panel = pt.lerp(panel, pt.hexc("#6d7068"), scratches * 0.35)                   # chipped to metal
    rust = pt.smooth(0.62, 0.8, pt.fbm(P, 9, 3, seed + 7))
    panel = pt.lerp(panel, pt.hexc("#5b3420"), rust * 0.6)
    # stencilled panel markings: a chevron and a code block, original design
    chev = (np.abs(np.abs(x) * 0.8 - (z - 0.25)) < 0.025) & (np.abs(x) < 0.16) & (y > D / 2 - 0.01) & (z > 0.18) & (z < 0.5)
    block = (np.abs(x - 0.42) < 0.08) & (np.abs(z - 0.47) < 0.03) & (y > D / 2 - 0.01) & (np.mod(x * 60, 1.0) > 0.35)
    panel = np.where((chev | block)[:, None], pt.lerp(pt.hexc("#d8d2b0"), panel, grime * 0.6), panel)
    frame = pt.lerp(pt.hexc("#2b2d2f"), pt.hexc("#121314"), grime)
    frame = pt.lerp(frame, pt.hexc("#6e7072"), scratches * 0.4)
    frame = pt.lerp(frame, pt.hexc("#4a2a18"), rust * 0.5)
    stripes = (np.mod((x + z) * 6.0, 1.0) < 0.5) if True else None
    hazard = np.where(stripes[:, None], pt.hexc("#d8a21c"), pt.hexc("#151515"))
    hazard = pt.lerp(hazard, pt.hexc("#4a4232"), grime * 0.5)
    out = np.where((part == FRAME)[:, None], frame, panel)
    out = np.where((part == HAZARD)[:, None], hazard, out)
    return np.clip(out, 0, 1)


def texture(ob, size, seed):
    lib.activate(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(50), island_margin=0.006)
    bpy.ops.object.mode_set(mode='OBJECT')
    pos, nor, part, valid = pt.rasterize(ob, size)
    # paint in world space so the lid matches the body
    P = pos[valid] + np.array(ob.location, np.float32)
    rgb = np.zeros((size, size, 3), np.float32)
    rgb[valid] = paint(P, part[valid], seed)
    ao_img = bpy.data.images.new("ao_" + ob.name, size, size)
    for slot in ob.material_slots:
        nt = slot.material.node_tree
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = ao_img
        nt.nodes.active = n
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 32
    lib.activate(ob)
    bpy.ops.object.bake(type='AO')
    ao = np.array(ao_img.pixels[:], np.float32).reshape(size, size, 4)[..., 0]
    rgb *= (0.4 + 0.6 * ao)[..., None]
    img = pt.to_image(bpy, ob.name + "_albedo", rgb, valid)
    mat = bpy.data.materials.new("supply_" + ob.name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.65
    bsdf.inputs["Metallic"].default_value = 0.2
    for i in range(len(ob.data.materials)):
        if i != GLOW:
            ob.data.materials[i] = mat


def main():
    body, lid, anchor = build()
    texture(body, 512, 11)
    texture(lid, 256, 11)
    print("supply box: %d + %d triangles" % (lib.tri_count(body), lib.tri_count(lid)))
    lib.activate(body, lid, anchor)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                              export_image_format='JPEG', export_jpeg_quality=88, export_animations=False)
    if "--preview" in sys.argv:
        d = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        lid.rotation_euler = (math.radians(105), 0, 0)  # open: +X lifts the front edge
        lib.render_setup((800, 600), samples=48)
        lib.add_camera((1.6, 2.2, 1.5), (0, 0, 0.4), lens=40)
        lib.add_light('AREA', (1.5, 2.0, 2.5), 250, (1.0, 0.85, 0.7), size=1.5)
        lib.add_light('AREA', (-2.0, -1.0, 2.0), 300, (0.5, 0.6, 1.0), size=1.0)
        pl = bpy.data.lights.new("glow", 'POINT')
        pl.energy = 40
        pl.color = (1.0, 0.55, 0.2)
        g = lib.link(bpy.data.objects.new("glow", pl))
        g.location = (0, 0, 0.5)
        bpy.ops.mesh.primitive_plane_add(size=10)
        bpy.context.active_object.data.materials.append(lib.grunge_material("floor", "#2a2b2c", "#121314", blood_amount=0.1, scale=3))
        lib.render(os.path.join(d, "supply_box.png"))


if __name__ == "__main__":
    main()
