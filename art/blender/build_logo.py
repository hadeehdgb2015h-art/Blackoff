"""Bot logo for Blackoff: the game's own soldier, black against a blood moon,
the dead rising around him, BLACK OFF in the game's Cinzel lettering.

Made for a Telegram profile photo: square, everything that matters inside
the centred circle Telegram crops to. Original work from the game's models.

Run:  /opt/blender-venv/bin/python art/blender/build_logo.py [size] [samples]
Output: art/logo/bot_logo.png (default 1024 px) and art/logo/bot_logo_640.png

With --card the same scene is rendered as the background of the shareable
result card (phase 25): 1080 x 1350, no title, the figures in the upper part
(the server writes the player's result over the dark lower part).
Output: server/assets/card/card_bg.jpg
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS = os.path.join(ROOT, "client", "assets", "models")
# a static bold instance of the game's Cinzel with overlaps removed (the
# variable font's overlapping outlines break Blender's text fill)
FONT = os.path.join(ROOT, "art", "logo", "Cinzel-Bold-static.ttf")
OUT = os.path.join(ROOT, "art", "logo")
CARD = "--card" in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
SIZE = int(ARGS[0]) if ARGS else 1024
SAMPLES = int(ARGS[1]) if len(ARGS) > 1 else 96


def emission(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def moon_material():
    """A blood moon: hot core, darker rim, faint craters from noise."""
    m = bpy.data.materials.new("moon")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (0.465, 0.465, 0.465)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 5.0
    noise.inputs["Detail"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.28, 0.025, 0.02, 1)
    ramp.color_ramp.elements[1].position = 0.55
    ramp.color_ramp.elements[1].color = (0.78, 0.13, 0.06, 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.35
    nt.links.new(tc.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs[0], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(ramp.outputs["Color"], mix.inputs[6])
    nt.links.new(noise.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], em.inputs["Color"])
    em.inputs["Strength"].default_value = 2.4
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def silhouette_material():
    """Almost black, slightly glossy: the rim light draws the edges."""
    m = bpy.data.materials.new("silhouette")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.012, 0.01, 0.012, 1)
    b.inputs["Roughness"].default_value = 0.45
    b.inputs["Specular IOR Level"].default_value = 0.7
    return m


def import_figure(name, action, frame, loc, rot_z, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    rig = None
    for o in new:
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if o.type == "ARMATURE":
            rig = o
    sil = silhouette_material()
    for o in bpy.data.objects:
        if o.type == "MESH" and o.parent == rig:
            for slot in o.material_slots:
                slot.material = sil
            if not o.material_slots:
                o.data.materials.append(sil)
    rig.location = loc
    rig.rotation_euler[2] = rot_z
    rig.scale = (scale, scale, scale)
    if rig.animation_data is None:
        rig.animation_data_create()
    act = next(a for a in bpy.data.actions if a.name == action or a.name.startswith(action + "."))
    rig.animation_data.action = act
    rig["frame"] = frame
    return rig


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1080 if CARD else SIZE
    scene.render.resolution_y = 1350 if CARD else SIZE
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"

    world = bpy.data.worlds.new("night")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.012, 0.006, 0.014, 1)
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world

    # the figures: the soldier in front, two of the dead behind him
    import_figure("soldier", "idle_long", 10, (0, 0, 0), math.radians(-28))
    import_figure("zombie_walker", "attack", 8, (-0.95, 1.2, 0), math.radians(24), 0.98)
    import_figure("zombie_runner", "attack", 8, (1.0, 1.5, 0), math.radians(-28), 0.96)
    scene.frame_set(12)

    # ground: a dark ridge that fades into mist
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    ground = bpy.context.object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes["Principled BSDF"]
    gb.inputs["Base Color"].default_value = (0.003, 0.002, 0.002, 1)
    gb.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(gm)

    # the blood moon behind the soldier's shoulders
    bpy.ops.mesh.primitive_circle_add(vertices=128, radius=2.15, fill_type="NGON", location=(0.15, 9.0, 2.35))
    moon = bpy.context.object
    moon.rotation_euler[0] = math.radians(90)
    moon.data.materials.append(moon_material())
    # a soft halo around it
    bpy.ops.mesh.primitive_circle_add(vertices=128, radius=4.6, fill_type="NGON", location=(0.15, 9.3, 2.35))
    halo = bpy.context.object
    halo.rotation_euler[0] = math.radians(90)
    hm = bpy.data.materials.new("halo")
    hm.use_nodes = True
    nt = hm.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mixs = nt.nodes.new("ShaderNodeMixShader")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.75, 0.12, 0.05, 1)
    em.inputs["Strength"].default_value = 1.3
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "QUADRATIC_SPHERE"
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (0.22, 0.22, 0.22)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs[0], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], mixs.inputs["Fac"])
    nt.links.new(tr.outputs[0], mixs.inputs[1])
    nt.links.new(em.outputs[0], mixs.inputs[2])
    nt.links.new(mixs.outputs[0], out.inputs[0])
    hm.blend_method = "BLEND"
    halo.data.materials.append(hm)

    # a faint rim of moonlight on the edges
    bpy.ops.object.light_add(type="AREA", location=(0.2, 4.0, 2.4))
    rim = bpy.context.object
    rim.data.energy = 70
    rim.data.size = 1.6
    rim.data.color = (1.0, 0.35, 0.18)
    rim.rotation_euler = (math.radians(-78), 0, math.radians(180))
    # mist hanging low over the ground
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 5.5, 0.3))
    mist = bpy.context.object
    mist.scale = (16, 12, 0.6)
    vm = bpy.data.materials.new("mist")
    vm.use_nodes = True
    vn = vm.node_tree
    vn.nodes.clear()
    vout = vn.nodes.new("ShaderNodeOutputMaterial")
    vol = vn.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.45, 0.16, 0.14, 1)
    vol.inputs["Density"].default_value = 0.08
    vn.links.new(vol.outputs[0], vout.inputs["Volume"])
    mist.data.materials.append(vm)

    # BLACK OFF in Cinzel, warm gold, low in the circle
    curve = bpy.data.curves.new("title", "FONT")
    curve.body = "BLACK OFF"
    curve.font = bpy.data.fonts.load(FONT)
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = 0.235
    curve.space_character = 1.12
    curve.extrude = 0.0
    title = bpy.data.objects.new("title", curve)
    scene.collection.objects.link(title)
    title.data.materials.append(emission("gold", (1.0, 0.6, 0.2), 1.45))

    # camera: a little low, looking up at him
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.0, -3.75, 0.82)
    target = Vector((0.0, 0.0, 1.42))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    # the title rides on the camera: always upright, low inside the circle crop
    title.parent = cam
    title.location = (0, -0.66, -3.0)
    if CARD:
        # no title (the card has its own), figures lifted into the upper part
        title.hide_render = True
        cam_data.shift_y = -0.2

    if CARD:
        path = os.path.join(ROOT, "server", "assets", "card", "card_bg.jpg")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.render.filepath = path
        scene.render.image_settings.file_format = "JPEG"
        scene.render.image_settings.quality = 88
        bpy.ops.render.render(write_still=True)
        print("wrote", path)
        return

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "bot_logo.png" if SIZE >= 1024 else "bot_logo_preview.png")
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("wrote", path)
    if SIZE >= 1024:
        img = bpy.data.images.load(path)
        img.scale(640, 640)
        small = os.path.join(OUT, "bot_logo_640.png")
        img.filepath_raw = small
        img.file_format = "PNG"
        img.save()
        print("wrote", small)


main()
