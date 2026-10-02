extends TestCase


func test_shared_data_valid() -> void:
	var d := defs()
	check(d.errors.is_empty(), "shared data errors: " + "; ".join(d.errors))
	check(d.weapons.has("pistol") and d.weapons.has("rifle"), "both slice weapons")
	check(d.zombies.has("walker") and d.zombies.has("runner"), "both slice zombies")
	eq(int(d.constants.sim.tickRate), 20, "tick rate")
	check(d.maps.has("facility_01"), "default map present")


func test_scenes_load() -> void:
	for path in ["res://scenes/boot/boot.tscn", "res://scenes/maps/facility_01.tscn"]:
		var s: PackedScene = load(path)
		check(s != null and s.can_instantiate(), path + " loads")
