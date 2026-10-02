"""Shared hard-surface modelling kit (weapons, props)."""
import math

import bpy
import bmesh
from mathutils import Vector

import lib


class Kit:
    """Hard-surface modelling helpers. Parts are tagged with a material index
    (used as a paint category) and a vertex group 'node_<name>' so a joined
    mesh can later be split back into named nodes."""

    def __init__(self, mat_names):
        self.parts = []
        self.mats = [lib.flat_material(n, "#808080") for n in mat_names]

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


