class_name MapDecor
extends RefCounted
## Instantiates art props for `map_prop` markers (meta "prop" = node name in one
## of the prop libraries below; names are unique across them). Purely visual:
## gameplay blockers are separate hidden boxes exported to shared/maps.
## Run before MapBatcher.

const LIBRARIES := ["res://assets/models/env_props.glb", "res://assets/models/dark_props.glb"]


static func decorate(map_root: Node3D) -> int:
	var meshes := {}
	for path in LIBRARIES:
		if not ResourceLoader.exists(path):
			continue
		var lib: Node = (load(path) as PackedScene).instantiate()
		for mi in lib.find_children("*", "MeshInstance3D", true, false):
			meshes[str(mi.name)] = (mi as MeshInstance3D).mesh
		lib.free()
	if meshes.is_empty():
		return 0
	var count := 0
	var stack: Array[Node] = [map_root]
	var markers: Array[Node3D] = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.is_in_group("map_prop"):
			markers.append(n)
	for m in markers:
		var prop_name := str(m.get_meta("prop", ""))
		if not meshes.has(prop_name):
			push_warning("MapDecor: unknown prop " + prop_name)
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Art_" + prop_name
		mi.mesh = meshes[prop_name]
		mi.transform = map_root.global_transform.affine_inverse() * m.global_transform
		mi.add_to_group("map_visual")
		map_root.add_child(mi)
		count += 1
	return count
