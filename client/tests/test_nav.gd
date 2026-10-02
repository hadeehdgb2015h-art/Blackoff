extends TestCase

var map: MapData
var nav: NavGrid


func _init() -> void:
	var d := defs()
	map = MapData.from_dict(d.maps.facility_01, 0.4)
	nav = NavGrid.new(map, float(d.constants.maps.navCellSize), float(d.constants.maps.navAgentRadius))


func test_every_entry_reaches_every_spawn() -> void:
	for e in map.zombie_entries:
		for s in map.player_spawns:
			var path := nav.find_path(e.pos, s.pos)
			check(not path.is_empty(), "path from %s to spawn %s" % [e.id, s.pos])


func test_path_does_not_cross_walls() -> void:
	var path := nav.find_path(map.zombie_entries[0].pos, map.player_spawns[0].pos)
	for i in range(1, path.size()):
		check(map.segment_clear(path[i - 1], path[i], 0.05), "segment %d clear" % i)


func test_interactables_reachable() -> void:
	for it in map.interactables:
		check(not nav.find_path(map.player_spawns[0].pos, it.pos).is_empty(), "reach " + it.id)
