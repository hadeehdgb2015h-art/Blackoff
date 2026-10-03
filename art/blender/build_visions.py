"""Sky visions for Blackoff (phase 21): six original dark-fantasy scenes that
appear one at a time beside the moon, as a faint glowing mirage.

The owner showed reference reels (blue moon over a sea of statues, a whale
swimming through the clouds, a glowing tree, a figure holding a lantern, an
eye in the sky). Those are another artist's work, so these are new scenes in
the same spirit, modelled and rendered here (Cycles, CPU). They are blue on
black: the game draws them additively, so black is transparent.

Run:  /opt/blender-venv/bin/python art/blender/build_visions.py [name ...]
Output: client/assets/textures/sky_vision_<name>.png (512 x 512, RGB)
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "client", "assets", "textures")
FONT = os.path.join(ROOT, "client", "assets", "fonts", "Cinzel.ttf")
SIZE = 512
SAMPLES = 64


# ------------------------------------------------------------------ scene helpers

def reset(seed):
    random.seed(seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = 0.0
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    return sc


def node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        if k in n.inputs:
            n.inputs[k].default_value = v
        else:
            setattr(n, k, v)
    return n


def link(nt, a, b):
    nt.links.new(a, b)


def sky(sc, dark=(0.002, 0.004, 0.02), light=(0.05, 0.11, 0.35), scale=2.2, stretch=(1, 1, 1), strength=1.0, contrast=0.55):
    """A cloudy night sky from noise on the view direction."""
    w = bpy.data.worlds.new("sky")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    tc = node(nt, "ShaderNodeTexCoord")
    mp = node(nt, "ShaderNodeMapping")
    mp.inputs["Scale"].default_value = stretch
    link(nt, tc.outputs["Generated"], mp.inputs["Vector"])
    nz = node(nt, "ShaderNodeTexNoise", Scale=scale, Detail=10.0, Roughness=0.62, Distortion=0.4)
    link(nt, mp.outputs["Vector"], nz.inputs["Vector"])
    ramp = node(nt, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = contrast - 0.15
    ramp.color_ramp.elements[0].color = (*dark, 1)
    ramp.color_ramp.elements[1].position = contrast + 0.25
    ramp.color_ramp.elements[1].color = (*light, 1)
    link(nt, nz.outputs["Fac"], ramp.inputs["Fac"])
    bg = node(nt, "ShaderNodeBackground", Strength=strength * 0.5)  # a mirage needs a dark surround
    link(nt, ramp.outputs["Color"], bg.inputs["Color"])
    out = node(nt, "ShaderNodeOutputWorld")
    link(nt, bg.outputs["Background"], out.inputs["Surface"])


def mat_emit(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = node(nt, "ShaderNodeEmission", Color=(*color, 1), Strength=strength)
    out = node(nt, "ShaderNodeOutputMaterial")
    link(nt, e.outputs["Emission"], out.inputs["Surface"])
    return m


def mat_solid(name, color, rough=0.55, bump=0.0, bump_scale=8.0, sheen=None):
    """Principled surface, optional noise bump and a faint emissive tint."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    if bump > 0:
        tc = node(nt, "ShaderNodeTexCoord")
        nz = node(nt, "ShaderNodeTexNoise", Scale=bump_scale, Detail=12.0, Roughness=0.7)
        link(nt, tc.outputs["Object"], nz.inputs["Vector"])
        b = node(nt, "ShaderNodeBump", Strength=bump)
        link(nt, nz.outputs["Fac"], b.inputs["Height"])
        link(nt, b.outputs["Normal"], p.inputs["Normal"])
    if sheen:
        p.inputs["Emission Color"].default_value = (*sheen[0], 1)
        p.inputs["Emission Strength"].default_value = sheen[1]
    return m


def mat_pattern_glow(name, base, glow, strength, scale=6.0, width=0.035, coords="Object"):
    """A dark surface traced with glowing cracks (voronoi edges)."""
    m = mat_solid(name, base, rough=0.45)
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = node(nt, "ShaderNodeTexCoord")
    vo = node(nt, "ShaderNodeTexVoronoi", Scale=scale)
    vo.feature = "DISTANCE_TO_EDGE"
    link(nt, tc.outputs[coords], vo.inputs["Vector"])
    lt = node(nt, "ShaderNodeMath", operation="LESS_THAN")
    lt.inputs[1].default_value = width
    link(nt, vo.outputs["Distance"], lt.inputs[0])
    p.inputs["Emission Color"].default_value = (*glow, 1)
    link(nt, lt.outputs["Value"], p.inputs["Emission Strength"])
    mul = node(nt, "ShaderNodeMath", operation="MULTIPLY")
    mul.inputs[1].default_value = strength
    link(nt, lt.outputs["Value"], mul.inputs[0])
    link(nt, mul.outputs["Value"], p.inputs["Emission Strength"])
    return m


def mat_bands(name, color, strength, scale=8.0, distortion=6.0, direction="Z"):
    """Glowing streaks (water falls, waves): an emissive wave texture."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tc = node(nt, "ShaderNodeTexCoord")
    wv = node(nt, "ShaderNodeTexWave", Scale=scale, Distortion=distortion, Detail=6.0)
    wv.bands_direction = direction
    link(nt, tc.outputs["Object"], wv.inputs["Vector"])
    ramp = node(nt, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (color[0] * 0.15, color[1] * 0.15, color[2] * 0.2, 1)
    ramp.color_ramp.elements[1].color = (*color, 1)
    link(nt, wv.outputs["Fac"], ramp.inputs["Fac"])
    e = node(nt, "ShaderNodeEmission", Strength=strength)
    link(nt, ramp.outputs["Color"], e.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    link(nt, e.outputs["Emission"], out.inputs["Surface"])
    return m


def mat_water(name, deep, glow, glow_strength, scale=3.0):
    """Dark glossy water with a glowing noise shimmer."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*deep, 1)
    p.inputs["Roughness"].default_value = 0.08
    tc = node(nt, "ShaderNodeTexCoord")
    mp = node(nt, "ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1, 3, 1)
    link(nt, tc.outputs["Object"], mp.inputs["Vector"])
    nz = node(nt, "ShaderNodeTexNoise", Scale=scale, Detail=8.0, Roughness=0.6, Distortion=1.2)
    link(nt, mp.outputs["Vector"], nz.inputs["Vector"])
    b = node(nt, "ShaderNodeBump", Strength=0.25)
    link(nt, nz.outputs["Fac"], b.inputs["Height"])
    link(nt, b.outputs["Normal"], p.inputs["Normal"])
    ramp = node(nt, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (*glow, 1)
    link(nt, nz.outputs["Fac"], ramp.inputs["Fac"])
    p.inputs["Emission Strength"].default_value = glow_strength
    link(nt, ramp.outputs["Color"], p.inputs["Emission Color"])
    return m


def obj_last():
    return bpy.context.active_object


def add(kind, mat, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), smooth=True, **kw):
    getattr(bpy.ops.mesh, "primitive_" + kind + "_add")(location=loc, rotation=rot, **kw)
    o = obj_last()
    o.scale = scale
    if mat:
        o.data.materials.append(mat)
    if smooth and hasattr(o.data, "polygons"):
        for f in o.data.polygons:
            f.use_smooth = True
    return o


def rough_up(o, strength=0.6, size=0.8, levels=2):
    """Craggy rock: subdivide and displace with clouds."""
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = levels
    sub.render_levels = levels
    tex = bpy.data.textures.new("clouds%d" % random.randint(0, 99999), "CLOUDS")
    tex.noise_scale = size
    tex.noise_depth = 4
    d = o.modifiers.new("disp", "DISPLACE")
    d.texture = tex
    d.strength = strength
    return o


def camera(sc, loc, target, lens=35.0):
    bpy.ops.object.camera_add(location=loc)
    cam = obj_last()
    cam.data.lens = lens
    cam.data.clip_end = 1000
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


def light(kind, loc, energy, color, size=1.0, target=None):
    bpy.ops.object.light_add(type=kind, location=loc)
    l = obj_last()
    l.data.energy = energy
    l.data.color = color
    if kind in ("POINT", "SPOT"):
        l.data.shadow_soft_size = size
    if kind == "SUN":
        l.data.angle = math.radians(size)
    if target is not None:
        d = Vector(target) - Vector(loc)
        l.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return l


def bloom(sc, size=8, threshold=0.6, mix=0.0):
    """Compositor glow around the brightest parts."""
    sc.use_nodes = True
    nt = sc.node_tree
    nt.nodes.clear()
    rl = nt.nodes.new("CompositorNodeRLayers")
    comp = nt.nodes.new("CompositorNodeComposite")
    g = nt.nodes.new("CompositorNodeGlare")
    for attr, val in (("glare_type", "FOG_GLOW"), ("quality", "HIGH"), ("size", size), ("threshold", threshold), ("mix", mix)):
        try:
            setattr(g, attr, val)
        except (AttributeError, TypeError):
            pass
    for sock, val in (("Threshold", threshold), ("Size", size / 9.0), ("Strength", 1.0)):
        if sock in g.inputs:
            try:
                g.inputs[sock].default_value = val
            except TypeError:
                pass
    nt.links.new(rl.outputs["Image"], g.inputs["Image"])
    nt.links.new(g.outputs["Image"], comp.inputs["Image"])


def render(sc, name):
    path = os.path.join(OUT, "sky_vision_%s.png" % name)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[visions] %s -> %s (%d KB)" % (name, os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))


# ------------------------------------------------------------------ scenes

def moon_sea():
    """A huge blue moon over a glowing sea, two hooded stone watchers, peaks."""
    sc = reset(11)
    sky(sc, light=(0.03, 0.07, 0.25), scale=1.6)
    # moon: pale blue disc with dark seas
    m = bpy.data.materials.new("moon")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tc = node(nt, "ShaderNodeTexCoord")
    nz = node(nt, "ShaderNodeTexNoise", Scale=2.6, Detail=12.0, Roughness=0.66)
    link(nt, tc.outputs["Object"], nz.inputs["Vector"])
    ramp = node(nt, "ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.42
    ramp.color_ramp.elements[0].color = (0.10, 0.18, 0.62, 1)
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = (0.62, 0.74, 1.0, 1)
    link(nt, nz.outputs["Fac"], ramp.inputs["Fac"])
    e = node(nt, "ShaderNodeEmission", Strength=1.25)
    link(nt, ramp.outputs["Color"], e.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    link(nt, e.outputs["Emission"], out.inputs["Surface"])
    add("uv_sphere", m, loc=(0, 60, 15), scale=(9, 9, 9), segments=64, ring_count=32)
    add("plane", mat_water("sea", (0.004, 0.012, 0.05), (0.15, 0.4, 1.0), 1.6, scale=2.2), loc=(0, 30, 0), scale=(80, 80, 1))
    stone = mat_solid("stone", (0.012, 0.016, 0.03), rough=0.5, bump=0.35, bump_scale=14, sheen=((0.05, 0.1, 0.35), 0.15))
    for x, y, s in ((-2.8, 17, 1.7), (2.4, 23, 1.35)):
        add("cone", stone, loc=(x, y, 1.4 * s), scale=(s, s, s), vertices=24, radius1=0.75, radius2=0.28, depth=2.8)
        add("uv_sphere", stone, loc=(x, y - 0.05 * s, 3.05 * s), scale=(0.42 * s, 0.42 * s, 0.55 * s))
    rock = mat_solid("rock", (0.015, 0.025, 0.06), rough=0.35, bump=0.6, bump_scale=6, sheen=((0.1, 0.25, 0.8), 0.05))
    for i in range(7):
        x = -46 + i * 15 + random.uniform(-4, 4)
        o = add("ico_sphere", rock, loc=(x, 75 + random.uniform(-8, 8), 0), scale=(9, 6, random.uniform(9, 16)), subdivisions=3)
        rough_up(o, strength=3.0, size=1.5)
    o = add("ico_sphere", rock, loc=(-6.5, 6, -0.6), scale=(4.5, 4, 2.4), subdivisions=3)
    rough_up(o, strength=0.9, size=0.7)
    light("POINT", (0, 52, 15), 15000, (0.5, 0.65, 1.0), size=6)
    camera(sc, (0.5, -4, 2.2), (0, 40, 9), lens=30)
    bloom(sc)
    render(sc, "moon_sea")


def sky_whale():
    """A great whale swimming through storm clouds, glowing seams on its hide,
    waterfalls pouring from cliffs below, pines in the dark."""
    sc = reset(23)
    sky(sc, light=(0.07, 0.16, 0.5), scale=1.8, stretch=(1, 1, 0.6), contrast=0.5)
    hide = mat_pattern_glow("hide", (0.006, 0.01, 0.025), (0.15, 0.35, 1.0), 9.0, scale=3.2, width=0.04)
    body = add("uv_sphere", hide, loc=(0, 34, 15), scale=(7.5, 2.4, 2.1), segments=64, ring_count=32)
    whale = [body]
    t = body.modifiers.new("taper", "SIMPLE_DEFORM")
    t.deform_method = "TAPER"
    t.deform_axis = "X"
    t.factor = -0.55
    body.rotation_euler = (math.radians(4), math.radians(-8), math.radians(-12))
    add("cone", hide, loc=(-9.5, 35.5, 15.6), rot=(0, math.radians(84), math.radians(-12)), scale=(1, 1, 1), vertices=32, radius1=1.4, radius2=0.35, depth=6)
    for side in (-1, 1):
        add("cube", hide, loc=(-13.0, 36.4 + side * 1.6, 16.0), rot=(math.radians(side * 30), 0, math.radians(-12 + side * 25)), scale=(1.6, 2.2, 0.12))
        add("cube", hide, loc=(1.5, 34 + side * 2.2, 13.8), rot=(math.radians(side * 50), math.radians(25), math.radians(-12)), scale=(2.2, 0.5, 0.08))
    add("uv_sphere", mat_emit("eye", (0.6, 0.85, 1.0), 25), loc=(6.4, 32.0, 15.6), scale=(0.18, 0.18, 0.18))
    cliff = mat_solid("cliff", (0.01, 0.02, 0.045), rough=0.6, bump=0.5, bump_scale=5)
    o = add("cube", cliff, loc=(0, 70, 4), scale=(30, 4, 9))
    rough_up(o, strength=1.5, size=1.2)
    falls = mat_bands("falls", (0.45, 0.7, 1.0), 4.0, scale=10, distortion=8, direction="Z")
    for x in (-7.5, -2.5, 2.5, 7.5):
        add("plane", falls, loc=(x, 65.5, 6), rot=(math.radians(90), 0, 0), scale=(1.6, 6, 1))
    add("plane", mat_water("river", (0.003, 0.01, 0.04), (0.2, 0.5, 1.0), 2.0, scale=4), loc=(0, 30, 0), scale=(14, 40, 1))
    pine = mat_solid("pine", (0.006, 0.016, 0.018), rough=0.8)
    for i in range(18):
        side = -1 if i % 2 else 1
        x = side * random.uniform(9, 22)
        y = random.uniform(10, 55)
        h = random.uniform(7, 13)
        for k in range(3):
            add("cone", pine, loc=(x, y, h * (0.35 + k * 0.22)), scale=(1, 1, 1), vertices=10, radius1=h * (0.28 - k * 0.07), radius2=0.0, depth=h * 0.45)
    light("SUN", (0, 0, 10), 0.6, (0.4, 0.55, 1.0), size=4, target=(0, 40, 8))
    camera(sc, (3, 14, 5.5), (0, 34, 13), lens=24)
    bloom(sc)
    render(sc, "sky_whale")


def glow_tree():
    """A vast tree on a floating mound, hung with glowing blue lights, roots
    dangling over still water."""
    sc = reset(37)
    sky(sc, light=(0.12, 0.2, 0.75), scale=1.4, stretch=(1, 3.5, 1), contrast=0.5, strength=1.1)
    bark = mat_solid("bark", (0.01, 0.014, 0.03), rough=0.7, bump=0.8, bump_scale=10)
    trunk = add("cylinder", bark, loc=(0, 30, 6), scale=(1.3, 1.3, 5), vertices=24)
    tw = trunk.modifiers.new("twist", "SIMPLE_DEFORM")
    tw.deform_method = "TWIST"
    tw.angle = math.radians(75)
    tp = trunk.modifiers.new("taper", "SIMPLE_DEFORM")
    tp.deform_method = "TAPER"
    tp.factor = -0.35
    mound = add("cylinder", mat_solid("mound", (0.008, 0.012, 0.03), rough=0.8, bump=0.7, bump_scale=4), loc=(0, 30, 3.0), scale=(8, 8, 1.0), vertices=40)
    rough_up(mound, strength=0.8, size=0.9)
    leaf = mat_solid("leaf", (0.004, 0.01, 0.03), rough=0.75, bump=0.5, bump_scale=18)
    for i in range(170):
        a = random.uniform(0, math.tau)
        u = random.uniform(-0.25, 1.0)
        r = math.sqrt(max(0.0, 1 - u * u)) * random.uniform(0.8, 1.0)
        p = (math.cos(a) * r * 8, 30 + math.sin(a) * r * 5.5, 12.5 + u * 4.2)
        add("ico_sphere", leaf, loc=p, scale=(1, 1, 1), subdivisions=2, radius=random.uniform(0.7, 1.5))
    lamp = mat_emit("lamp", (0.35, 0.65, 1.0), 14)
    for i in range(46):
        a = random.uniform(0, math.tau)
        u = random.uniform(-0.6, 0.85)
        r = math.sqrt(max(0.0, 1 - u * u))
        p = (math.cos(a) * r * 8.6, 30 + math.sin(a) * r * 6.0 - 1.0, 12.5 + u * 4.4)
        add("uv_sphere", lamp, loc=p, scale=(1, 1, 1), radius=random.uniform(0.18, 0.32), segments=12, ring_count=8)
    root = mat_solid("root", (0.008, 0.012, 0.03), rough=0.8)
    for i in range(34):
        a = random.uniform(0, math.tau)
        r = random.uniform(5, 7.8)
        ln = random.uniform(1.5, 3.5)
        add("cylinder", root, loc=(math.cos(a) * r, 30 + math.sin(a) * r, 2.2 - ln / 2), scale=(1, 1, 1), vertices=6, radius=0.06, depth=ln)
    add("plane", mat_water("swamp", (0.004, 0.008, 0.035), (0.2, 0.4, 1.0), 1.2, scale=2.5), loc=(0, 30, 0), scale=(70, 70, 1))
    light("POINT", (0, 30, 14), 2500, (0.35, 0.6, 1.0), size=6)
    camera(sc, (0, 4, 3.2), (0, 30, 10.5), lens=30)
    bloom(sc)
    render(sc, "glow_tree")


def lantern_keeper():
    """A cloaked keeper on a moonlit shore, back turned, holding a blue lantern
    up on a staff towards the sea."""
    sc = reset(41)
    sky(sc, dark=(0.01, 0.008, 0.04), light=(0.2, 0.18, 0.6), scale=1.7, contrast=0.5)
    cloak = mat_solid("cloak", (0.01, 0.012, 0.03), rough=0.6, bump=0.6, bump_scale=7, sheen=((0.06, 0.12, 0.4), 0.02))
    add("cone", cloak, loc=(0, 0, 1.15), vertices=40, radius1=0.75, radius2=0.22, depth=2.3)
    add("uv_sphere", cloak, loc=(0, 0.02, 2.42), scale=(0.3, 0.3, 0.34))
    add("cone", cloak, loc=(0, 0.06, 2.78), rot=(math.radians(-14), 0, 0), vertices=16, radius1=0.24, radius2=0.0, depth=0.5)
    add("cylinder", cloak, loc=(0.42, 0.05, 1.95), rot=(0, math.radians(-38), 0), vertices=10, radius=0.1, depth=0.9)
    staff = mat_solid("staff", (0.02, 0.016, 0.012), rough=0.7)
    add("cylinder", staff, loc=(0.78, 0.15, 1.6), rot=(0, math.radians(-8), 0), vertices=8, radius=0.035, depth=3.1)
    metal = mat_solid("metal", (0.02, 0.025, 0.04), rough=0.3)
    add("cube", metal, loc=(0.98, 0.15, 3.0), scale=(0.16, 0.16, 0.22))
    add("cube", mat_emit("glass", (0.35, 0.7, 1.0), 30), loc=(0.98, 0.15, 3.0), scale=(0.17, 0.14, 0.17))
    add("cone", metal, loc=(0.98, 0.15, 3.3), vertices=4, radius1=0.22, radius2=0.02, depth=0.2)
    light("POINT", (0.98, 0.0, 3.0), 260, (0.35, 0.65, 1.0), size=0.12)
    add("plane", mat_solid("sand", (0.05, 0.065, 0.2), rough=0.9, bump=0.6, bump_scale=3), loc=(0, 6, 0), scale=(40, 14, 1))
    add("plane", mat_water("sea", (0.01, 0.02, 0.08), (0.3, 0.45, 1.0), 1.4, scale=1.5), loc=(0, 40, 0.05), scale=(70, 20, 1))
    rock = mat_solid("tower", (0.015, 0.02, 0.05), rough=0.5, bump=0.7, bump_scale=4)
    for x, y, h in ((-10, 30, 9), (11, 36, 12), (-4, 44, 5)):
        o = add("cylinder", rock, loc=(x, y, h / 2), scale=(1.8, 1.8, h / 2), vertices=16)
        rough_up(o, strength=0.8, size=0.8)
    add("uv_sphere", mat_emit("moonglow", (0.75, 0.8, 1.0), 9), loc=(4, 80, 16), scale=(3, 3, 3))
    light("SUN", (0, 30, 10), 0.4, (0.55, 0.6, 1.0), size=2, target=(0, 0, 0))
    camera(sc, (-1.6, -4.6, 1.9), (0.6, 8, 2.6), lens=30)
    bloom(sc)
    render(sc, "lantern_keeper")


def watcher():
    """A giant eye opening in a storm of blue cloud."""
    sc = reset(53)
    sky(sc, dark=(0.0, 0.0, 0.01), light=(0.1, 0.18, 0.6), scale=2.6, contrast=0.55)
    m = bpy.data.materials.new("iris")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tc = node(nt, "ShaderNodeTexCoord")
    sep = node(nt, "ShaderNodeSeparateXYZ")
    link(nt, tc.outputs["Object"], sep.inputs["Vector"])
    # distance from the eye's axis (it looks down -Y, at the camera)
    sx = node(nt, "ShaderNodeMath", operation="MULTIPLY")
    link(nt, sep.outputs["X"], sx.inputs[0])
    link(nt, sep.outputs["X"], sx.inputs[1])
    sz = node(nt, "ShaderNodeMath", operation="MULTIPLY")
    link(nt, sep.outputs["Z"], sz.inputs[0])
    link(nt, sep.outputs["Z"], sz.inputs[1])
    s2 = node(nt, "ShaderNodeMath", operation="ADD")
    link(nt, sx.outputs["Value"], s2.inputs[0])
    link(nt, sz.outputs["Value"], s2.inputs[1])
    r = node(nt, "ShaderNodeMath", operation="SQRT")
    link(nt, s2.outputs["Value"], r.inputs[0])
    nz = node(nt, "ShaderNodeTexNoise", Scale=9.0, Detail=12.0, Roughness=0.7, Distortion=2.0)
    link(nt, tc.outputs["Object"], nz.inputs["Vector"])
    radial = node(nt, "ShaderNodeMath", operation="ADD")
    link(nt, r.outputs["Value"], radial.inputs[0])
    mn = node(nt, "ShaderNodeMath", operation="MULTIPLY")
    mn.inputs[1].default_value = 0.12
    link(nt, nz.outputs["Fac"], mn.inputs[0])
    link(nt, mn.outputs["Value"], radial.inputs[1])
    ramp = node(nt, "ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0, 0, 0, 1)
    cr.elements[1].position = 0.28
    cr.elements[1].color = (0.0, 0.0, 0.0, 1)
    for pos, col in ((0.34, (0.25, 0.5, 1.0, 1)), (0.55, (0.08, 0.2, 0.75, 1)), (0.7, (0.5, 0.75, 1.0, 1)), (0.76, (0.02, 0.04, 0.15, 1)), (1.0, (0.01, 0.02, 0.07, 1))):
        e = cr.elements.new(pos)
        e.color = col
    link(nt, radial.outputs["Value"], ramp.inputs["Fac"])
    em = node(nt, "ShaderNodeEmission", Strength=3.0)
    link(nt, ramp.outputs["Color"], em.inputs["Color"])
    out = node(nt, "ShaderNodeOutputMaterial")
    link(nt, em.outputs["Emission"], out.inputs["Surface"])
    add("uv_sphere", m, loc=(0, 30, 0), scale=(4.2, 4.2, 4.2), segments=96, ring_count=48)
    lid = mat_solid("lid", (0.01, 0.02, 0.06), rough=0.8, bump=1.0, bump_scale=3, sheen=((0.1, 0.25, 0.8), 0.02))
    for side in (-1, 1):
        o = add("uv_sphere", lid, loc=(0, 26.5, side * 4.6), scale=(10, 2.5, 3.2), segments=48, ring_count=24)
        rough_up(o, strength=0.35, size=0.9, levels=1)
    cloud = mat_solid("cloud", (0.02, 0.04, 0.12), rough=0.9, bump=1.0, bump_scale=2, sheen=((0.12, 0.3, 0.9), 0.02))
    light("POINT", (0, 26, 0), 3000, (0.3, 0.55, 1.0), size=3)  # the eye lights the clouds around it
    for i in range(14):
        a = i / 14 * math.tau
        o = add("ico_sphere", cloud, loc=(math.cos(a) * 11, 31, math.sin(a) * 7.5), scale=(3.5, 2, 2.4), subdivisions=3)
        rough_up(o, strength=1.2, size=0.9)
    camera(sc, (0, 0, 0), (0, 30, 0), lens=30)
    bloom(sc, size=9)
    render(sc, "watcher")


def logo():
    """BLACK OFF in glowing Cinzel letters among the clouds, the moon behind."""
    sc = reset(61)
    sky(sc, light=(0.06, 0.13, 0.42), scale=2.0, contrast=0.55)
    bpy.ops.object.text_add(location=(0, 0, 0))
    t = obj_last()
    t.data.body = "BLACK OFF"
    if os.path.exists(FONT):
        t.data.font = bpy.data.fonts.load(FONT)
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.extrude = 0.06
    t.data.bevel_depth = 0.015
    t.rotation_euler = (math.radians(90), 0, 0)
    t.data.materials.append(mat_emit("letters", (0.5, 0.72, 1.0), 2.6))
    add("uv_sphere", mat_emit("moon", (0.25, 0.4, 1.0), 1.2), loc=(0, 18, 0.4), scale=(3.2, 3.2, 3.2), segments=48, ring_count=24)
    cloud = mat_solid("cloud", (0.02, 0.04, 0.12), rough=0.9, bump=1.0, bump_scale=2, sheen=((0.1, 0.25, 0.8), 0.02))
    light("POINT", (0, -1.5, 0), 400, (0.45, 0.65, 1.0), size=2)  # the letters light the clouds
    for i in range(10):
        o = add("ico_sphere", cloud, loc=(random.uniform(-7, 7), random.uniform(3, 10), random.choice((-1, 1)) * random.uniform(1.4, 3.6)), scale=(3, 1.5, 1.1), subdivisions=3)
        rough_up(o, strength=0.8, size=0.8)
    camera(sc, (0, -7.5, 0), (0, 0, 0), lens=40)
    bloom(sc, size=6, threshold=0.9)
    render(sc, "logo")


SCENES = {"moon_sea": moon_sea, "sky_whale": sky_whale, "glow_tree": glow_tree, "lantern_keeper": lantern_keeper, "watcher": watcher, "logo": logo}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    for name in argv or list(SCENES):
        SCENES[name]()


main()
