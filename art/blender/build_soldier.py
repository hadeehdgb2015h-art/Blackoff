"""Soldier character for other players in online play (art stage 4).

Run:  /opt/blender-venv/bin/python art/blender/build_soldier.py [--preview DIR]
Output: client/assets/models/soldier.glb  (actions: idle, run, downed)

Reuses the zombie body, head and 23-bone rig (build_zombies.py) with healthy
proportions, a combat helmet with a cyan ally marker, a tactical vest with
pouches, a belt kit, a small pack and a balaclava. Faces +Y (Godot -Z).
The game attaches the held weapon (the first-person model, authored around the
eye at 1.6 m) to the character root, so the arms here are solved with a
two-bone IK onto that weapon's grip and handguard in every key pose.
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
import build_zombies as bz  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "client", "assets", "models", "soldier.glb")
TEX = 1024

BODY, HEAD, HELMET, VEST, GEAR, EYES, MARK = range(7)
EYE = Vector((0, 0, 1.6))          # where the game hangs the weapon (constants.player.eyeHeight)
GUN_SHIFT = Vector((0.03, -0.05, -0.03))  # third-person hold: a little lower and closer than first person
# Hand targets in weapon (camera) space, measured from vm_rifle.glb's arms.
GRIP = Vector((0.123, 0.293, -0.155))      # trigger hand (+X side bones: ".L")
FORE = Vector((0.062, 0.594, -0.088))      # support hand (".R")


# ---------------------------------------------------------------- geometry

def helmet():
    c = bz.HEAD_C
    bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=14, radius=1.0, location=(0, c.y - 0.006, c.z + 0.018))
    shell = bpy.context.active_object
    shell.scale = (0.122, 0.134, 0.118)
    lib.activate(shell)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    me = shell.data
    for v in me.vertices:  # cut away below the brow line (front higher than the back)
        lim = -0.005 + 0.03 * max(0.0, v.co.y / 0.134)
        if v.co.z < lim:
            v.co.z = lim
    for p in me.polygons:
        p.use_smooth = True
    bpy.ops.mesh.primitive_cylinder_add(vertices=28, radius=1.0, depth=0.012, location=(0, c.y - 0.006, c.z + 0.012))
    rim = bpy.context.active_object
    rim.scale = (0.128, 0.14, 1.0)
    lib.activate(rim)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # night-vision mount on the front, side rails
    parts = [shell, rim]
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, c.y + 0.125, c.z + 0.075))
    nv = bpy.context.active_object
    nv.scale = (0.05, 0.025, 0.04)
    parts.append(nv)
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(sx * 0.122, c.y - 0.005, c.z + 0.04))
        rail = bpy.context.active_object
        rail.scale = (0.012, 0.09, 0.018)
        parts.append(rail)
    for o in parts:
        lib.activate(o)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return lib.join(parts, "helmet")


def marker():
    c = bz.HEAD_C
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, c.y - 0.135, c.z + 0.05))
    m = bpy.context.active_object
    m.scale = (0.05, 0.012, 0.022)
    lib.activate(m)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    m.name = "marker"
    return m


def box(name, center, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.scale = size
    lib.activate(o)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bev = o.modifiers.new("bev", 'BEVEL')
    bev.width = min(size) * 0.18
    bev.segments = 2
    lib.apply_modifiers(o)
    o.name = name
    return o


def vest():
    plate = bz.ring("vest", 1.3, 0.215, 0.152, 0.34, segments=28, thickness=0.03)
    parts = [plate]
    for i, x in enumerate((-0.11, -0.04, 0.04, 0.11)):          # magazine pouches on the front
        parts.append(box("pouch%d" % i, (x, 0.165, 1.2), (0.06, 0.04, 0.11)))
    parts.append(box("radio", (0.19, 0.09, 1.3), (0.05, 0.05, 0.13)))
    parts.append(box("collar", (0, 0.0, 1.47), (0.3, 0.2, 0.05)))
    for sx in (-1, 1):                                            # shoulder straps
        parts.append(box("strap", (sx * 0.12, 0.0, 1.46), (0.06, 0.26, 0.04)))
    return lib.join(parts, "vest")


def gear():
    belt = bz.ring("belt", 0.99, 0.172, 0.122, 0.05, segments=26, thickness=0.014)
    parts = [belt]
    for x, y in ((0.15, 0.06), (-0.15, 0.06), (0.17, -0.05), (-0.17, -0.05)):
        parts.append(box("bpouch", (x, y, 0.95), (0.05, 0.05, 0.08)))
    parts.append(box("pack", (0, -0.2, 1.27), (0.26, 0.11, 0.3)))      # small assault pack
    parts.append(box("packtop", (0, -0.2, 1.43), (0.22, 0.09, 0.04)))
    for sx in (-1, 1):
        parts.append(box("kneepad", (sx * 0.1, 0.07, 0.53), (0.075, 0.035, 0.09)))
        parts.append(box("holster", (sx * 0.19, 0.0, 0.83), (0.04, 0.09, 0.15)) if sx > 0 else box("dump", (sx * 0.18, -0.03, 0.88), (0.05, 0.08, 0.09)))
    return lib.join(parts, "gear")


MATS = ("body", "head", "helmet", "vest", "gear", "eyes", "mark")


def _assign(ob, idx, mats):
    ob.data.materials.clear()
    for m in mats:
        ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.material_index = idx
        p.use_smooth = True


def build_mesh():
    """Returns the skinnable base (body + head, auto weights) and the rigid gear
    parts, which get explicit bone weights (heat weighting fails on overlapping gear)."""
    lib.reset()
    mats = [lib.flat_material(n, "#808080") for n in MATS]
    body = bz.build_body("walker")
    head = bz.build_head(mouth_open=0.0)
    _assign(body, BODY, mats)
    _assign(head, HEAD, mats)
    base = lib.join([body, head], "soldier")
    rigid = [(bz.build_eyes(), EYES, "head"), (helmet(), HELMET, "head"), (marker(), MARK, "head"), (vest(), VEST, "chest"), (gear(), GEAR, None)]
    for ob, idx, _ in rigid:
        _assign(ob, idx, mats)
    return base, rigid


def attach_rigid(base, rigid):
    """Helmet/eyes/marker on the head, vest and pack on the chest, belt kit on
    the hips, knee pads on the shins; then join into the skinned mesh."""
    for ob, _, bone in rigid:
        names = {}
        for v in ob.data.vertices:
            co = ob.matrix_world @ v.co
            b = bone or ("shin.L" if co.x > 0 else "shin.R") if co.z < 0.65 else (bone or ("chest" if co.z > 1.15 else "hips"))
            names.setdefault(b, []).append(v.index)
        for b, idx in names.items():
            ob.vertex_groups.new(name=b).add(idx, 1.0, 'REPLACE')
    joined = lib.join([base] + [o for o, _, _ in rigid], "soldier")
    return joined


# ---------------------------------------------------------------- painting

def paint(P, N_, part):
    N = len(P)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    n1 = pt.fbm(P, 7, 4, 3)
    n2 = pt.fbm(P, 14, 3, 9)
    # urban-woodland camo: three blotch layers over olive
    camo = np.tile(pt.hexc("#3b4332"), (N, 1))
    camo = np.where((pt.fbm(P, 5, 3, 21) > 0.55)[:, None], pt.hexc("#5a5843"), camo)
    camo = np.where((pt.fbm(P, 6, 3, 33) > 0.6)[:, None], pt.hexc("#23281f"), camo)
    camo = np.where((pt.fbm(P, 9, 3, 47) > 0.66)[:, None], pt.hexc("#151714"), camo)
    camo = camo * (0.9 + 0.2 * n2)[:, None]
    seams = (np.abs(np.mod(z * 9, 1.0) - 0.5) < 0.02) & (z > 0.2)
    camo = np.where(seams[:, None], camo * 0.75, camo)
    boots = z < 0.17
    gloves = (np.abs(x) > 0.47) & (z < 1.08)
    body = np.where(boots[:, None], pt.lerp(pt.hexc("#1c1b19"), pt.hexc("#2c2a26"), n1), camo)
    body = np.where(gloves[:, None], pt.lerp(pt.hexc("#1a1a1b"), pt.hexc("#2a2a2c"), n1), body)
    # balaclava with an eye slot
    hc = bz.HEAD_C
    eye_band = (np.abs(z - (hc.z + 0.008)) < 0.026) & (y > hc.y + 0.03) & (np.abs(x) < 0.075)
    skin = pt.lerp(pt.hexc("#9c7258"), pt.hexc("#7d5843"), n1)
    head = np.where(eye_band[:, None], skin, pt.lerp(pt.hexc("#26272a"), pt.hexc("#1c1d20"), n1))
    helmet_c = pt.lerp(pt.hexc("#4b5040"), pt.hexc("#3a3e31"), n1)
    helmet_c = np.where((z < hc.z + 0.03)[:, None], helmet_c * 0.7, helmet_c)  # rim and mounts darker
    vest_c = pt.lerp(pt.hexc("#34362d"), pt.hexc("#262822"), n1)
    vest_c = np.where((np.abs(np.mod(z * 40, 1.0) - 0.5) < 0.08)[:, None], vest_c * 0.85, vest_c)  # webbing rows
    gear_c = pt.lerp(pt.hexc("#2f312a"), pt.hexc("#1f201c"), n1)
    out = np.zeros((N, 3), np.float32)
    for cat, c in ((BODY, body), (HEAD, head), (HELMET, helmet_c), (VEST, vest_c), (GEAR, gear_c)):
        sel = part == cat
        out[sel] = c[sel]
    return np.clip(out, 0, 1)


def texture(ob):
    head_v = set()
    for p in ob.data.polygons:
        if p.material_index in (HEAD, HELMET):
            head_v.update(p.vertices)
    saved = {i: ob.data.vertices[i].co.copy() for i in head_v}
    for i in head_v:
        ob.data.vertices[i].co = bz.HEAD_C + (saved[i] - bz.HEAD_C) * 1.6
    lib.activate(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=0.005)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.004, shape_method='CONCAVE')
    bpy.ops.object.mode_set(mode='OBJECT')
    for i, co in saved.items():
        ob.data.vertices[i].co = co
    ao = lib.bake_ao(ob, TEX, samples=32)
    pos, nor, part, valid = pt.rasterize(ob, TEX)
    rgb = np.zeros((TEX, TEX, 3), np.float32)
    rgb[valid] = paint(pos[valid], nor[valid], part[valid]) * (0.4 + 0.6 * ao[valid])[:, None]
    img = pt.to_image(bpy, "soldier_albedo", rgb, valid)
    mat = bpy.data.materials.new("soldier")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.82
    eyes = lib.flat_material("soldier_eyes", "#1a1410", roughness=0.3)
    mark = lib.flat_material("ally_marker", "#38e8ff", emission="#38e8ff", strength=6.0)
    for i in range(len(ob.data.materials)):
        ob.data.materials[i] = eyes if i == EYES else (mark if i == MARK else mat)


# ---------------------------------------------------------------- animation

def weapon_point(p):
    """Weapon/camera space (x right, y forward, z up in Blender) -> character space."""
    return EYE + GUN_SHIFT + p


def ik_arm(ao, side, target, pole):
    """Two-bone IK: aims for upper_arm/forearm/hand so the hand reaches `target`."""
    pb = ao.pose.bones
    s = ao.matrix_world.inverted() @ (ao.matrix_world @ pb["upper_arm." + side].head)
    l1 = (pb["upper_arm." + side].bone.tail_local - pb["upper_arm." + side].bone.head_local).length
    l2 = (pb["forearm." + side].bone.tail_local - pb["forearm." + side].bone.head_local).length
    wrist = target
    d_vec = wrist - s
    d = min(d_vec.length, (l1 + l2) * 0.999)
    dirn = d_vec.normalized()
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    perp = (pole - dirn * pole.dot(dirn)).normalized()
    elbow = s + dirn * a + perp * h
    hand_end = s + dirn * d
    return {"upper_arm." + side: {"aim": tuple(elbow - s)}, "forearm." + side: {"aim": tuple(hand_end - elbow)},
            "hand." + side: {"aim": (0.0, 1.0, -0.15)}}


def hold(ao, body_rots, hips_offset):
    """Pose the body, then solve both arms onto the weapon."""
    lib.set_pose(ao, body_rots, hips_offset)
    bpy.context.view_layer.update()
    grip = weapon_point(GRIP) - Vector((0, 0.06, 0.0))   # wrist sits behind the palm
    fore = weapon_point(FORE) - Vector((0, 0.07, 0.0))
    arms = lib.merge(ik_arm(ao, "L", grip, Vector((0.6, -0.1, -0.8))), ik_arm(ao, "R", fore, Vector((-0.7, 0.0, -0.7))))
    return lib.merge(body_rots, arms)


# torso bladed toward the weapon so the support hand reaches the handguard
STANCE_UP = {"spine": (2, 0, -10), "chest": (0, 0, -14), "neck": (0, 0, 10), "head": (-4, 0, 16)}


def build_actions(ao):
    acts = []
    stance = bz.legs(6, -8, -4, -8)
    off = bz.plant(stance)
    acts.append(lib.new_action(ao, "idle"))
    for f, breathe in ((0, 0), (30, 1), (60, 0)):
        up = lib.merge(STANCE_UP, {"chest": (-1.5 * breathe, 0, -14)})
        lib.key_pose(ao, f, hold(ao, lib.merge(up, stance), off), off)
    # run: athletic sprint with the rifle held at the chest. 20 frames = 0.67 s.
    acts.append(lib.new_action(ao, "run"))
    run_up = {"spine": (-12, 0, -8), "chest": (-4, 0, -14), "neck": (8, 0, 8), "head": (10, 0, 14)}
    for f, lg, o in (
        (0, bz.legs(38, -18, -28, -60, 10, 20), -0.02),
        (5, bz.legs(10, -14, 4, -95, 0, 25), 0.03),
        (10, bz.legs(-28, -60, 38, -18, 20, 10), -0.02),
        (15, bz.legs(4, -95, 10, -14, 25, 0), 0.03),
        (20, bz.legs(38, -18, -28, -60, 10, 20), -0.02),
    ):
        off_r = bz.plant(lg, o)
        lib.key_pose(ao, f, hold(ao, lib.merge(run_up, lg), off_r), off_r)
    # downed: on the back, propped on one elbow (the game hides the weapon)
    acts.append(lib.new_action(ao, "downed"))
    floor_arms = bz.arms((0.85, 0.1, -0.1), (0.75, 0.45, -0.05), (0.6, 0.6, 0.0), (-0.6, -0.5, -0.3), (-0.3, 0.2, 0.9), (0.0, 0.3, 0.95))
    pose = lib.merge(floor_arms, bz.legs(-2, -14, 6, -40, 30, 20), {"hips": (75, 0, 8), "spine": (-12, 0, 0), "head": (-20, 10, 10)})
    lib.key_pose(ao, 0, pose, (0, -0.75, -0.8))
    lib.key_pose(ao, 40, lib.merge(pose, {"head": (-24, -6, 10)}), (0, -0.75, -0.8))
    lib.finish_actions(ao, acts)
    return acts


def preview(ao, out_png, act, frame, cam=(1.4, 2.6, 1.5), target=(0, 0.2, 1.0)):
    for o in [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT') or o.name.startswith("Plane")]:
        bpy.data.objects.remove(o, do_unlink=True)
    lib.render_setup((640, 800), samples=32)
    lib.add_camera(cam, target, lens=40)
    lib.add_light('AREA', (1.8, 2.4, 2.6), 260, (1.0, 0.85, 0.7), size=1.6)
    lib.add_light('AREA', (-1.8, -1.4, 2.2), 500, (0.55, 0.65, 1.0), size=1.0)
    bpy.ops.mesh.primitive_plane_add(size=10)
    ao.animation_data.action = act
    bpy.context.scene.frame_set(frame)
    lib.render(out_png)
    ao.animation_data.action = None


def gun_proxy():
    """The first-person rifle, placed where the game will hang it (preview only)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "client", "assets", "models", "vm_rifle.glb"))
    for o in set(bpy.data.objects) - before:
        if o.type == 'MESH' and o.name.startswith("Arm"):
            o.hide_render = True
        if o.parent is None:
            o.location = EYE + GUN_SHIFT


def main():
    base, rigid = build_mesh()
    bz.fix_part_weights = lambda ob: None  # gear is weighted explicitly below
    ao = bz.build_armature(base)
    ob = attach_rigid(base, rigid)
    texture(ob)
    acts = {a.name: a for a in build_actions(ao)}
    for o in list(bpy.data.objects):  # helpers left by the bakes must not be exported
        if o not in (ob, ao):
            bpy.data.objects.remove(o, do_unlink=True)
    print("soldier: %d triangles" % lib.tri_count(ob))
    bz.export(ob, ao, OUT)
    if "--preview" in sys.argv:
        d = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        # Preview what the game gets: the exported GLB plus the rifle where the game hangs it.
        lib.reset()
        bpy.ops.import_scene.gltf(filepath=OUT)
        ao = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
        acts = {a.name: a for a in bpy.data.actions}
        if ao.animation_data is None:
            ao.animation_data_create()
        gun_proxy()
        preview(ao, os.path.join(d, "soldier_idle.png"), acts["idle"], 1)
        preview(ao, os.path.join(d, "soldier_run.png"), acts["run"], 5, cam=(2.4, 1.0, 1.3))
        preview(ao, os.path.join(d, "soldier_downed.png"), acts["downed"], 1, cam=(2.0, 1.6, 1.4), target=(0, -0.4, 0.3))
        preview(ao, os.path.join(d, "soldier_face.png"), acts["idle"], 1, cam=(0.3, 0.9, 1.7), target=(0, 0, 1.62))


if __name__ == "__main__":
    main()
