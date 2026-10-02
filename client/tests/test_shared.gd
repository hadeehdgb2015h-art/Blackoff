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
