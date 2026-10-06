class_name MapBatcher
extends RefCounted
## Merges a map's static meshes into one mesh per (material, region). Regions
## are CHUNK-metre squares, so each merged mesh only spans nearby lights (the
## Compatibility renderer lights an object with at most 8 lights). Gameplay
## data is unaffected: it comes from shared/maps/<id>.json.
## Phones (phase 15): every merged mesh is one WebGL draw call, and draw calls
## are what a phone pays for, so chunks are large, and decoration props
## (map_visual) go into their own meshes that vanish beyond PROP_RANGE metres.

## Phase 32: fewer draw calls again. Walls and floors are merged across the
## whole map (one mesh per material: the game never runs more than 8 extra
## lights at once, the per-object limit, so nothing is lost); only decoration
## keeps its CHUNK squares (it is hidden by distance). And every glowing flat
## colour (emit_* materials: eyes, flames, lamps...) shares ONE material: its
## colour and glow strength ride in the vertex colours.
const GROUPS := ["map_wall", "map_floor", "map_visual"]
const EMIT_MAX := 8.0      ## glow strength stored as alpha * EMIT_MAX
static var _emit_mat: ShaderMaterial
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
		var prop := mi.is_in_group("map_visual") and not (mi.is_in_group("map_wall") or mi.is_in_group("map_floor"))
		# structure: one cell for the whole map; decoration: CHUNK squares
		var cell := Vector2i(floori(center.x / CHUNK), floori(center.z / CHUNK)) if prop else Vector2i.ZERO
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			var emit := _is_flat_emissive(mat)
			var key := "%s|%d|%d" % ["emit" if emit else str(mat.get_instance_id() if mat else 0), cell.x, cell.y]
			var outdoor: bool = center.z < OUTDOOR_Z or bool(mi.get_meta("outdoor", false))
			key += "|o" if outdoor else ""
			key += "|p" if prop else ""
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = [st, emit_material() if emit else mat, outdoor, prop]
			if emit:
				(tools[key][0] as SurfaceTool).append_from(_coloured(mi.mesh, si, mat as BaseMaterial3D), 0, xf)
			else:
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


## A flat glowing colour from the art pipeline (lib.flat_material "emit_*"):
## no texture, its look is the colour and the glow strength.
static func _is_flat_emissive(mat: Material) -> bool:
	var m := mat as BaseMaterial3D
	return m != null and m.resource_name.begins_with("emit_") and m.emission_enabled and m.albedo_texture == null and m.emission_texture == null


## The surface as a one-surface mesh whose vertex colours carry the material.
static func _coloured(mesh: Mesh, si: int, mat: BaseMaterial3D) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(si)
	var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var c := mat.emission if mat.emission != Color.BLACK else mat.albedo_color
	var col := Color(c.r, c.g, c.b, clampf(mat.emission_energy_multiplier / EMIT_MAX, 0.0, 1.0))
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(col)
	arrays[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## The one material every flat glowing colour shares.
static func emit_material() -> ShaderMaterial:
	if _emit_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
uniform float emit_max = %.1f;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.6;
	EMISSION = COLOR.rgb * COLOR.a * emit_max;
}
""" % EMIT_MAX
		_emit_mat = ShaderMaterial.new()
		_emit_mat.shader = sh
		_emit_mat.resource_name = "emit_shared"
	return _emit_mat
