class_name MapBatcher
extends RefCounted
## Merges a map's static meshes into one mesh per (material, region). Regions
## are CHUNK-metre squares, so each merged mesh only spans nearby lights (the
## Compatibility renderer lights an object with at most 8 lights). Gameplay
## data is unaffected: it comes from shared/maps/<id>.json.

const GROUPS := ["map_wall", "map_floor", "map_visual"]
const CHUNK := 12.0
const OUTDOOR_Z := -6.2   ## meshes north of the building facade also get layer 2 (moonlight)


static func batch(map_root: Node3D) -> int:
	var tools := {}  ## "matid|cx|cz" -> [SurfaceTool, Material]
	var victims: Array[Node] = []
	var stack: Array[Node] = [map_root]
	var inv := map_root.global_transform.affine_inverse()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var in_group := false
		for g in GROUPS:
			in_group = in_group or mi.is_in_group(g)
		if not in_group:
			continue
		victims.append(mi)
		if not mi.visible:
			continue  # hidden collision-only boxes are simply dropped
		var xf := inv * mi.global_transform
		var center := xf * mi.mesh.get_aabb().get_center()
		var cell := Vector2i(floori(center.x / CHUNK), floori(center.z / CHUNK))
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			var key := "%d|%d|%d" % [mat.get_instance_id() if mat else 0, cell.x, cell.y]
			var outdoor := center.z < OUTDOOR_Z
			key += "|o" if outdoor else ""
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = [st, mat, outdoor]
			(tools[key][0] as SurfaceTool).append_from(mi.mesh, si, xf)
	for key in tools:
		var st: SurfaceTool = tools[key][0]
		var mat: Material = tools[key][1]
		st.set_material(mat)
		var out := MeshInstance3D.new()
		out.name = "Batched_%s_%s" % [mat.resource_name if mat else "nomat", key.replace("|", "_")]
		out.mesh = st.commit()
		if tools[key][2]:
			out.layers = 1 | 2
		map_root.add_child(out)
	for v in victims:
		v.get_parent().remove_child(v)
		v.queue_free()
	return tools.size()
