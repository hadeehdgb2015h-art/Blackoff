class_name MapBatcher
extends RefCounted
## Merges a map scene's static greybox meshes into one mesh per material
## (tens of draw calls instead of hundreds). Gameplay data is unaffected:
## it comes from shared/maps/<id>.json.

const GROUPS := ["map_wall", "map_floor", "map_visual"]


static func batch(map_root: Node3D) -> int:
	var by_mat := {}
	var victims: Array[Node] = []
	var stack: Array[Node] = [map_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var in_group := false
		for g in GROUPS:
			in_group = in_group or mi.is_in_group(g)
		if not in_group:
			continue
		var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
		if not by_mat.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[mat] = st
		(by_mat[mat] as SurfaceTool).append_from(mi.mesh, 0, map_root.global_transform.affine_inverse() * mi.global_transform)
		victims.append(mi)
	for mat in by_mat:
		var st: SurfaceTool = by_mat[mat]
		st.set_material(mat)
		var out := MeshInstance3D.new()
		out.name = "Batched_" + (mat.resource_name if mat else "nomat")
		out.mesh = st.commit()
		map_root.add_child(out)
	# Hidden collision-only meshes (e.g. the supply box block) are dropped too.
	stack = [map_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and not n.visible and n.is_in_group("map_wall"):
			victims.append(n)
	for v in victims:
		v.get_parent().remove_child(v)
		v.queue_free()
	return by_mat.size()
