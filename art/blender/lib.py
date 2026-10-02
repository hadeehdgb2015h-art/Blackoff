"""Shared helpers for Blackoff's procedural art (run with Blender's bpy module).

Conventions: metres, Z up, characters face +Y (exports to glTF -Z, which is
Godot's forward for our views). Every asset is original and generated here.
"""
import math
import random

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = 30
    sc.unit_settings.system = 'METRIC'


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def activate(ob, *others):
    bpy.ops.object.select_all(action='DESELECT')
    for o in others:
        o.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def apply_modifiers(ob):
    activate(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def join(objs, name):
    activate(objs[0], *objs[1:])
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ------------------------------------------------------------------ materials

def node_mat(name, build):
    """Creates a node material; build(nodes, links, out_socket_target) wires it."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    build(nt.nodes, nt.links, bsdf)
    return m


def color_rgba(hexstr):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    # sRGB -> linear for node colours
    lin = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


def grunge_material(name, base, dark, blood_amount=0.25, scale=6.0, roughness=0.85, blood_scale=3.0, seed=0.0):
    """Base colour with mottled dirt and blood splatter, all procedural (baked later)."""
    def build(nodes, links, bsdf):
        tc = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Location"].default_value = (seed, seed * 1.7, seed * 0.3)
        links.new(tc.outputs["Object"], mapping.inputs["Vector"])
        dirt = nodes.new("ShaderNodeTexNoise")
        dirt.inputs["Scale"].default_value = scale
        dirt.inputs["Detail"].default_value = 8.0
        dirt.inputs["Roughness"].default_value = 0.6
        links.new(mapping.outputs[0], dirt.inputs["Vector"])
        mix_dirt = nodes.new("ShaderNodeMix")
        mix_dirt.data_type = 'RGBA'
        mix_dirt.inputs["A"].default_value = color_rgba(base)
        mix_dirt.inputs["B"].default_value = color_rgba(dark)
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[1].position = 0.75
        links.new(dirt.outputs["Fac"], ramp.inputs[0])
        links.new(ramp.outputs[0], mix_dirt.inputs["Factor"])
        # fine fabric / pore grain
        grain = nodes.new("ShaderNodeTexNoise")
        grain.inputs["Scale"].default_value = scale * 12
        links.new(mapping.outputs[0], grain.inputs["Vector"])
        grain_mix = nodes.new("ShaderNodeMix")
        grain_mix.data_type = 'RGBA'
        grain_mix.blend_type = 'MULTIPLY'
        grain_mix.inputs["Factor"].default_value = 0.25
        links.new(mix_dirt.outputs["Result"], grain_mix.inputs["A"])
        links.new(grain.outputs["Color"], grain_mix.inputs["B"])
        # blood splatter
        blood = nodes.new("ShaderNodeTexVoronoi")
        blood.inputs["Scale"].default_value = blood_scale
        blood_noise = nodes.new("ShaderNodeTexNoise")
        blood_noise.inputs["Scale"].default_value = blood_scale * 2.5
        blood_noise.inputs["Detail"].default_value = 6
        links.new(mapping.outputs[0], blood_noise.inputs["Vector"])
        bsum = nodes.new("ShaderNodeMath")
        bsum.operation = 'ADD'
        links.new(mapping.outputs[0], blood.inputs["Vector"])
        links.new(blood.outputs["Distance"], bsum.inputs[0])
        links.new(blood_noise.outputs["Fac"], bsum.inputs[1])
        bramp = nodes.new("ShaderNodeValToRGB")
        bramp.color_ramp.elements[0].position = 0.42
        bramp.color_ramp.elements[0].color = (1, 1, 1, 1)
        bramp.color_ramp.elements[1].position = 0.42 + 0.06
        bramp.color_ramp.elements[1].color = (0, 0, 0, 1)
        links.new(bsum.outputs[0], bramp.inputs[0])
        bfac = nodes.new("ShaderNodeMath")
        bfac.operation = 'MULTIPLY'
        bfac.inputs[1].default_value = blood_amount * 2.0
        links.new(bramp.outputs[0], bfac.inputs[0])
        bmix = nodes.new("ShaderNodeMix")
        bmix.data_type = 'RGBA'
        bmix.inputs["B"].default_value = color_rgba("#3a0604")
        links.new(grain_mix.outputs["Result"], bmix.inputs["A"])
        links.new(bfac.outputs[0], bmix.inputs["Factor"])
        links.new(bmix.outputs["Result"], bsbase(bsdf))
        bsdf.inputs["Roughness"].default_value = roughness
    return node_mat(name, build)


def bsbase(bsdf):
    return bsdf.inputs["Base Color"]


def flat_material(name, hexcol, roughness=0.6, metallic=0.0, emission=None, strength=4.0):
    def build(nodes, links, bsdf):
        bsdf.inputs["Base Color"].default_value = color_rgba(hexcol)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission:
            bsdf.inputs["Emission Color"].default_value = color_rgba(emission)
            bsdf.inputs["Emission Strength"].default_value = strength
    return node_mat(name, build)


# ------------------------------------------------------------------ baking

def bake_atlas(ob, size, keep_materials, out_name, ao_strength=0.55, samples=24):
    """Bakes every material except keep_materials into one albedo atlas
    (diffuse colour * ambient occlusion) and swaps in a single material."""
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    activate(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')
    color = bpy.data.images.new(out_name + "_col", size, size)
    ao = bpy.data.images.new(out_name + "_ao", size, size)
    baked_slots = [s for s in ob.material_slots if s.material and s.material.name not in keep_materials]

    def target(img):
        for s in baked_slots:
            nt = s.material.node_tree
            n = nt.nodes.get("__bake__") or nt.nodes.new("ShaderNodeTexImage")
            n.name = "__bake__"
            n.image = img
            nt.nodes.active = n
    target(color)
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    sc.render.bake.margin = 4
    bpy.ops.object.bake(type='DIFFUSE')
    target(ao)
    bpy.ops.object.bake(type='AO')
    # combine: albedo * lerp(1, ao, strength)
    import numpy as np
    c = np.array(color.pixels[:]).reshape(-1, 4)
    a = np.array(ao.pixels[:]).reshape(-1, 4)[:, :1]
    c[:, :3] *= (1.0 - ao_strength) + ao_strength * a
    final = bpy.data.images.new(out_name, size, size)
    final.pixels = c.reshape(-1).tolist()
    final.file_format = 'PNG'
    # single baked material
    mat = bpy.data.materials.new(out_name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = final
    nt.links.new(tex.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    # Collapse to unique materials (baked atlas + kept ones) and remap faces,
    # so the export has one primitive per material.
    old = [s.material for s in ob.material_slots]
    new_list = [mat] + [m for m in old if m and m.name in keep_materials]
    remap = [0 if (m is None or m.name not in keep_materials) else new_list.index(m) for m in old]
    for poly in ob.data.polygons:
        poly.material_index = remap[poly.material_index]
    ob.data.materials.clear()
    for m in new_list:
        ob.data.materials.append(m)
    return final


# ------------------------------------------------------------------ rigging / animation

def set_pose(arm_ob, rots, hips_offset=(0, 0, 0)):
    """rots: bone -> spec, applied relative to the rest pose. Bones not listed reset.
    spec = (rx, ry, rz): degrees about ARMATURE axes (X right, Y forward, Z up),
           rotating the bone in its rest frame (children follow).
    spec = {"aim": (x, y, z)}: point the bone along this armature-space direction
           *after* its parents are posed (intuitive for arms)."""
    posed = {}  # bone name -> posed armature-space 3x3 rotation of the bone frame
    for pb in arm_ob.pose.bones:  # parents come first (creation order)
        pb.rotation_mode = 'QUATERNION'
        Lc = pb.bone.matrix_local.to_3x3()
        if pb.parent:
            Lp = pb.parent.bone.matrix_local.to_3x3()
            M0 = posed[pb.parent.name] @ Lp.inverted() @ Lc
        else:
            M0 = Lc
        spec = rots.get(pb.name, (0, 0, 0))
        if isinstance(spec, dict):
            target = Vector(spec["aim"]).normalized()
            local = (M0.inverted() @ target).normalized()
            B = Vector((0, 1, 0)).rotation_difference(local).to_matrix()
        else:
            R = Euler(tuple(math.radians(v) for v in spec), 'XYZ').to_matrix()
            B = Lc.inverted() @ R @ Lc
        pb.rotation_quaternion = B.to_quaternion()
        posed[pb.name] = M0 @ B
        if pb.name == "hips":
            pb.location = Lc.inverted() @ Vector(hips_offset)
        else:
            pb.location = (0, 0, 0)


def key_pose(arm_ob, frame, rots, hips_offset=(0, 0, 0)):
    set_pose(arm_ob, rots, hips_offset)
    for pb in arm_ob.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if pb.name == "hips":
            pb.keyframe_insert("location", frame=frame)


def mirror(rots):
    """Mirror a pose across the X=0 plane (swap .L/.R, flip Y/Z rotations)."""
    out = {}
    for name, spec in rots.items():
        if name.endswith(".L"):
            other = name[:-2] + ".R"
        elif name.endswith(".R"):
            other = name[:-2] + ".L"
        else:
            other = name
        if isinstance(spec, dict):
            x, y, z = spec["aim"]
            out[other] = {"aim": (-x, y, z)}
        else:
            rx, ry, rz = spec
            out[other] = (rx, -ry, -rz)
    return out


def merge(*dicts):
    out = {}
    for d in dicts:
        out.update(d)
    return out


def new_action(arm_ob, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm_ob.animation_data is None:
        arm_ob.animation_data_create()
    arm_ob.animation_data.action = act
    return act


def finish_actions(arm_ob, actions):
    """Linear-ish interpolation for crisp mocap-like timing; push to NLA so the
    glTF exporter writes every action as its own animation."""
    for act in actions:
        for fc in getattr(act, "fcurves", []):
            for kp in fc.keyframe_points:
                kp.interpolation = 'BEZIER'
                kp.easing = 'AUTO'
    ad = arm_ob.animation_data
    for act in actions:
        tr = ad.nla_tracks.new()
        tr.name = act.name
        tr.strips.new(act.name, int(act.frame_range[0]), act)
        tr.mute = True
    ad.action = None


# ------------------------------------------------------------------ preview renders

def render_setup(res=(720, 720), samples=32):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.014, 0.018, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sc.world = world
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'


def add_light(kind, loc, energy, color=(1, 1, 1), size=1.0, rot=None):
    ld = bpy.data.lights.new(kind + "_l", kind)
    ld.energy = energy
    ld.color = color
    if kind == 'AREA':
        ld.size = size
    ob = link(bpy.data.objects.new(kind, ld))
    ob.location = loc
    if rot:
        ob.rotation_euler = rot
    else:
        look_at(ob, Vector((0, 0, 1.0)))
    return ob


def look_at(ob, target):
    d = (Vector(target) - ob.location).normalized()
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def add_camera(loc, target, lens=50):
    cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    cam.data.lens = lens
    cam.location = loc
    look_at(cam, target)
    bpy.context.scene.camera = cam
    return cam


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------ hard-surface helpers

def bake_pointiness(ob, size, contrast=(0.515, 0.58)):
    """Bakes a convex-edge mask (Cycles pointiness) for edge-wear painting.
    Returns a float32 (size, size) array in UV space."""
    import numpy as np
    img = bpy.data.images.new("edges_" + ob.name, size, size, float_buffer=True)
    saved = [s.material for s in ob.material_slots]
    tmp = bpy.data.materials.new("__pointiness__")
    tmp.use_nodes = True
    nt = tmp.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = contrast[0]
    ramp.color_ramp.elements[1].position = contrast[1]
    nt.links.new(geo.outputs["Pointiness"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emit.inputs[0])
    nt.links.new(emit.outputs[0], out.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    for s in ob.material_slots:
        s.material = tmp
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 4
    sc.render.bake.margin = 3
    activate(ob)
    bpy.ops.object.bake(type='EMIT')
    for s, m in zip(ob.material_slots, saved):
        s.material = m
    return np.array(img.pixels[:], np.float32).reshape(size, size, 4)[..., 0]


def bake_ao(ob, size, samples=32):
    import numpy as np
    img = bpy.data.images.new("ao_" + ob.name, size, size)
    for s in ob.material_slots:
        nt = s.material.node_tree
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        nt.nodes.active = n
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.render.bake.margin = 3
    activate(ob)
    bpy.ops.object.bake(type='AO')
    return np.array(img.pixels[:], np.float32).reshape(size, size, 4)[..., 0]


def pbr_material(name, albedo_img, orm_img=None, emissive=None):
    """Principled material with base colour and optional ORM-style texture
    (G = roughness, B = metallic), which the glTF exporter packs as metallicRoughness."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = albedo_img
    nt.links.new(t.outputs[0], bsdf.inputs["Base Color"])
    if orm_img is not None:
        o = nt.nodes.new("ShaderNodeTexImage")
        o.image = orm_img  # created Non-Color by painter.to_image
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(o.outputs[0], sep.inputs[0])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def separate_by_groups(ob, names):
    """Splits a joined mesh into objects by vertex groups 'node_<name>'.
    Returns {name: object}."""
    out = {}
    for name in names:
        g = ob.vertex_groups.get("node_" + name)
        if g is None:
            continue
        activate(ob)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='DESELECT')
        ob.vertex_groups.active_index = g.index
        bpy.ops.object.vertex_group_select()
        bpy.ops.mesh.separate(type='SELECTED')
        bpy.ops.object.mode_set(mode='OBJECT')
        new = [o for o in bpy.context.selected_objects if o != ob][0]
        new.name = name
        out[name] = new
    return out


def push_object_actions(ob, actions):
    """Turns {track_name: action} into muted NLA tracks so the glTF exporter
    merges same-named tracks of different objects into one animation."""
    if ob.animation_data is None:
        ob.animation_data_create()
    for name, act in actions.items():
        tr = ob.animation_data.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, int(act.frame_range[0]), act)
        tr.mute = True
    ob.animation_data.action = None
