extends SceneTree
## Exports a map scene's gameplay data to shared/maps/<map_id>.json, which
## both the client simulation and the server read.
##   godot --headless --path client --script res://tools/maps/export_map.gd -- <scene> <out.json>
## Groups read: map_floor (walkable boxes), map_wall (blocking boxes, AABB),
## map_player_spawn, map_zombie_entry (meta entry_id, inside),
## map_interact (meta interact_id, kind, item, radius), map_safe_area (meta min, max).
## Walls must be axis-aligned (rotation multiple of 90 degrees).

const FLOOR_HEIGHT := 3.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <res://scene.tscn> <output.json>")
		quit(2)
		return
	var packed: PackedScene = load(args[0])
	if packed == null:
		printerr("cannot load ", args[0])
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	var errors := PackedStringArray()
	var data := _export(scene, errors)
	if errors.size() > 0:
		for e in errors:
			printerr("export_map: ", e)
		quit(1)
		return
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false) + "\n")
	f.close()
	scene.free()
	print("export_map: wrote %s (%d walls, %d floors)" % [args[1], data.walls.size(), data.walkable.size()])
	quit(0)


func _export(scene: Node3D, errors: PackedStringArray) -> Dictionary:
	var walls := []
	var floors := []
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for n in _group(scene, "map_wall"):
		var box := _aabb(n, errors)
		walls.append({"min": _r3(box.position), "max": _r3(box.end)})
	for n in _group(scene, "map_floor"):
		var box := _aabb(n, errors)
		floors.append({"min": _r2(Vector2(box.position.x, box.position.z)), "max": _r2(Vector2(box.end.x, box.end.z))})
		mn = mn.min(Vector2(box.position.x, box.position.z))
		mx = mx.max(Vector2(box.end.x, box.end.z))
	var spawns := []
	for n in _group(scene, "map_player_spawn"):
		spawns.append({"pos": _r2(_xz(n)), "yaw": snappedf(_xform(n).basis.get_euler().y, 0.001)})
	var entries := []
	for n in _group(scene, "map_zombie_entry"):
		entries.append({"id": str(n.get_meta("entry_id", n.name)), "pos": _r2(_xz(n)), "inside": _r2(n.get_meta("inside"))})
	var interact := []
	for n in _group(scene, "map_interact"):
		var it := {"id": str(n.get_meta("interact_id", n.name)), "kind": str(n.get_meta("kind")),
			"pos": _r2(_xz(n)), "radius": float(n.get_meta("radius", 1.8))}
		if n.has_meta("item"):
			it["item"] = str(n.get_meta("item"))
		if n.has_meta("yaw"):
			it["yaw"] = snappedf(float(n.get_meta("yaw")), 0.001)
		interact.append(it)
	var safe := _group(scene, "map_safe_area")
	if safe.size() != 1:
		errors.append("exactly one map_safe_area marker required")
		return {}
	if spawns.is_empty() or entries.is_empty() or floors.is_empty():
		errors.append("map needs player spawns, zombie entries and floors")
	return {
		"schemaVersion": 1,
		"id": str(scene.get_meta("map_id", scene.name)),
		"floorHeight": FLOOR_HEIGHT,
		"bounds": {"min": _r2(mn), "max": _r2(mx)},
		"walkable": floors,
		"walls": walls,
		"playerSpawns": spawns,
		"zombieEntries": entries,
		"interactables": interact,
		"safeArea": {"min": _r2(safe[0].get_meta("min")), "max": _r2(safe[0].get_meta("max"))},
	}


## Nodes of group g under scene (works without entering the SceneTree).
func _group(scene: Node, g: String) -> Array:
	var out := []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != scene and n.is_in_group(g):
			out.append(n)
		stack.append_array(n.get_children())
	out.sort_custom(func(a, b): return str(scene.get_path_to(a)) < str(scene.get_path_to(b)))
	return out


## Transform relative to the scene root (the scene is never added to the tree).
func _xform(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D and p.get_parent() != null:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _aabb(n: Node3D, errors: PackedStringArray) -> AABB:
	var basis := _xform(n).basis
	for axis in [basis.x, basis.y, basis.z]:
		var a: Vector3 = axis.normalized().abs()
		if absf(maxf(a.x, maxf(a.y, a.z)) - 1.0) > 0.001:
			errors.append("%s is not axis-aligned" % n.name)
			break
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		errors.append("%s has no mesh" % n.name)
		return AABB()
	return _xform(n) * mi.mesh.get_aabb()


func _xz(n: Node3D) -> Vector2:
	var o := _xform(n).origin
	return Vector2(o.x, o.z)


func _r2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
