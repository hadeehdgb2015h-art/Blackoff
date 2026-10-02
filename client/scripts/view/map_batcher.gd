class_name MapBatcher
extends RefCounted
## Merges a map's static meshes into one mesh per (material, region). Regions
## are CHUNK-metre squares, so each merged mesh only spans nearby lights (the
## Compatibility renderer lights an object with at most 8 lights). Gameplay
## data is unaffected: it comes from shared/maps/<id>.json.
## Phones (phase 15): every merged mesh is one WebGL draw call, and draw calls
## are what a phone pays for, so chunks are large, and decoration props
## (map_visual) go into their own meshes that vanish beyond PROP_RANGE metres.

const GROUPS := ["map_wall", "map_floor", "map_visual"]
const CHUNK := 36.0
const PROP_RANGE := 38.0   ## decoration meshes are not drawn beyond this distance
const OUTDOOR_Z := -6.2   ## meshes north of the building facade also get layer 2 (moonlight)
                          ## (the generator tags other open-air meshes with meta "outdoor")


## Transform of `node` relative to `root`, from local transforms only: works
## whether or not the map is in the scene tree (MapCache prepares it outside).
static func rel_xf(root: Node, node: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			x = (n as Node3D).transform * x
		n = n.get_parent()
	return x


static func batch(map_root: Node3D) -> int:
	var tools := {}  ## "matid|cx|cz" -> [SurfaceTool, Material]
	var victims: Array[Node] = []
	var stack: Array[Node] = [map_root]
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
		var xf := rel_xf(map_root, mi)
		var center := xf * mi.mesh.get_aabb().get_center()
		var cell := Vector2i(floori(center.x / CHUNK), floori(center.z / CHUNK))
		var prop := mi.is_in_group("map_visual") and not (mi.is_in_group("map_wall") or mi.is_in_group("map_floor"))
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			var key := "%d|%d|%d" % [mat.get_instance_id() if mat else 0, cell.x, cell.y]
			var outdoor: bool = center.z < OUTDOOR_Z or bool(mi.get_meta("outdoor", false))
			key += "|o" if outdoor else ""
			key += "|p" if prop else ""
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = [st, mat, outdoor, prop]
			(tools[key][0] as SurfaceTool).append_from(mi.mesh, si, xf)
	for key in tools:
		var st: SurfaceTool = tools[key][0]
		var mat: Material = tools[key][1]
		st.set_material(mat)
		var out := MeshInstance3D.new()
		out.name = "Batched_%s_%s" % [mat.resource_name if mat else "nomat", key.replace("|", "_")]
		# compressed vertex attributes: half the size and half the GPU memory
		# traffic per vertex (phones are bandwidth bound)
		out.mesh = st.commit(null, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		if tools[key][2]:
			out.layers = 1 | 2
		if tools[key][3]:
			out.visibility_range_end = PROP_RANGE
			out.visibility_range_end_margin = 4.0
		map_root.add_child(out)
	for v in victims:
		v.get_parent().remove_child(v)
		v.queue_free()
	return tools.size()
