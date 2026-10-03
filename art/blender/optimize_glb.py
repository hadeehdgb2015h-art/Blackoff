"""Phone budget pass for the game's models (phase 17).

Opens each GLB, reduces every mesh to its share of a triangle budget with
Blender's Decimate (collapse) and scales every texture to at most MAX_TEX
pixels, then writes the GLB back with the same nodes, skins and animations.
Measured before: the soldier had 35 k triangles and two 2048 px textures
(44 MB of GPU memory per teammate), weapons 7-13 k triangles with 1024 px
textures, zombies 9-11 k each with up to 24 on screen.

Run:  /opt/blender-venv/bin/python art/blender/optimize_glb.py [name ...]
      (no names: every model in BUDGET)
"""
import os
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS = os.path.join(ROOT, "client", "assets", "models")
MAX_TEX = 512

# texture cap per file when it differs from MAX_TEX: the prop libraries share
# one atlas across dozens of props, so each prop needs more of its pixels
TEX_CAP = {"env_props.glb": 1024, "dark_props.glb": 1024}

# triangle budget per file (whole file)
BUDGET = {
    "soldier.glb": 7000,
    "zombie_walker.glb": 3500,
    "zombie_runner.glb": 3800,
    "vm_pistol.glb": 3200,
    "vm_rifle.glb": 4500,
    "vm_shotgun.glb": 3800,
    "vm_smg.glb": 3800,
    "vm_lmg.glb": 4500,
    "vm_sniper.glb": 3800,
    "vm_arc.glb": 4000,
    "vm_gale.glb": 4000,
    "vm_ember.glb": 4500,
    "env_props.glb": 11000,
    "dark_props.glb": 14000,
    "backdrop.glb": 5000,
}


def tri_count(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def optimize(name, budget):
    path = os.path.join(MODELS, name)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    before = sum(tri_count(o) for o in meshes)
    ratio = min(1.0, budget / max(1, before))
    if ratio < 0.98:
        for o in meshes:
            if tri_count(o) < 60:
                continue  # tiny parts (muzzle markers, eyes) keep their shape
            bpy.context.view_layer.objects.active = o
            mod = o.modifiers.new("phone_budget", "DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = ratio
            mod.use_collapse_triangulate = True
            # decimate before the armature deform, then bake it into the mesh
            while o.modifiers.find(mod.name) > 0:
                bpy.ops.object.modifier_move_up(modifier=mod.name)
            bpy.ops.object.modifier_apply(modifier=mod.name)
    after = sum(tri_count(o) for o in meshes)
    scaled = []
    cap = TEX_CAP.get(name, MAX_TEX)
    for img in bpy.data.images:
        w, h = img.size
        if max(w, h) > cap:
            k = cap / max(w, h)
            img.scale(max(1, int(w * k)), max(1, int(h * k)))
            img.pack()
            scaled.append("%s %dx%d" % (img.name, w, h))
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_image_format="JPEG",
        export_jpeg_quality=88,
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_yup=True,
        export_apply=False,
    )
    print("[optimize] %-20s tris %6d -> %6d  textures scaled: %s  size %d KB" % (
        name, before, after, ", ".join(scaled) or "none", os.path.getsize(path) // 1024))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    names = [a for a in argv if a.endswith(".glb")] or list(BUDGET)
    for n in names:
        optimize(n, BUDGET[n])


main()
