extends TestCase


func test_shared_data_valid() -> void:
	var d := defs()
	check(d.errors.is_empty(), "shared data errors: " + "; ".join(d.errors))
	check(d.weapons.has("pistol") and d.weapons.has("rifle"), "both slice weapons")
	check(d.zombies.has("walker") and d.zombies.has("runner"), "both slice zombies")
	eq(int(d.constants.sim.tickRate), 20, "tick rate")
	check(d.maps.has("facility_01"), "default map present")


func test_all_scenes_and_scripts_load() -> void:
	var stack := ["res://scenes", "res://scripts"]
	var count := 0
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			stack.append(dir + "/" + sub)
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".tscn"):
				var res := load(dir + "/" + f)
				check(res != null, dir + "/" + f + " loads")
				if res is PackedScene:
					check(res.can_instantiate(), f + " instantiates")
				count += 1
	check(count > 20, "found scripts and scenes (%d)" % count)


func test_visuals_cover_shared_defs() -> void:
	var v := Visuals.data()
	for id in defs().weapons:
		check(v.weapons.has(id), "visuals for weapon " + id)
	for id in defs().zombies:
		check(v.zombies.has(id), "visuals for zombie " + id)


func test_art_models_have_required_parts() -> void:
	var v := Visuals.data()
	for id in v.zombies:
		var path: String = v.zombies[id].get("model", "")
		if path == "":
			continue
		var scene: PackedScene = load(path)
		check(scene != null, "zombie model loads: " + path)
		if scene == null:
			continue
		var inst := scene.instantiate()
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(ap != null, id + " has an AnimationPlayer")
		if ap:
			for anim in ["idle", "attack", "hit", "death", str(v.zombies[id].get("locomotion", "walk"))]:
				check(ap.has_animation(anim), "%s has animation %s" % [id, anim])
		inst.free()
	var soldier: Dictionary = v.get("players", {}).get("soldier", {})
	var sm: PackedScene = load(str(soldier.get("model", "")))
	check(sm != null, "soldier model loads")
	if sm:
		var si := sm.instantiate()
		var sap := si.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(sap != null, "soldier has an AnimationPlayer")
		if sap:
			check(sap.has_animation("downed"), "soldier has downed")
			for hold in soldier.holds:
				for a in ["idle_", "run_"]:
					check(sap.has_animation(a + hold), "soldier has %s%s" % [a, hold])
		for wid in soldier.weaponHold:
			check(soldier.holds.has(soldier.weaponHold[wid]), "hold class for " + wid)
		si.free()
	var box: PackedScene = load(BoxView.MODEL)
	check(box != null, "supply box model loads")
	if box:
		var b := box.instantiate()
		check(b.find_child("Lid", true, false) != null, "supply box has a Lid node")
		b.free()


func test_map_props_and_fx_resolve() -> void:
	var meshes := {}
	for path in MapDecor.LIBRARIES:
		var lib: Node = (load(path) as PackedScene).instantiate()
		for mi in lib.find_children("*", "MeshInstance3D", true, false):
			meshes[str(mi.name)] = true
		lib.free()
	var backdrop: Node = (load(Atmosphere.BACKDROP) as PackedScene).instantiate()
	var map: Node = (load("res://scenes/maps/facility_01.tscn") as PackedScene).instantiate()
	var stack: Array[Node] = [map]
	var props := 0
	var fx := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.is_in_group("map_prop"):
			props += 1
			check(meshes.has(str(n.get_meta("prop"))), "prop mesh exists: " + str(n.get_meta("prop")))
		if n.is_in_group("map_fx"):
			fx += 1
			check(str(n.get_meta("fx")) in Atmosphere.KINDS, "known fx kind: " + str(n.get_meta("fx")))
			if str(n.get_meta("fx")) == "backdrop":
				check(backdrop.find_child(str(n.get_meta("node")), true, false) != null, "backdrop node exists: " + str(n.get_meta("node")))
	check(props > 50, "map has art props")
	check(fx > 20, "map has fx markers")
	map.free()
	backdrop.free()
