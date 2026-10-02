extends TestCase

var map: MapData


func _init() -> void:
	map = MapData.from_dict(defs().maps.facility_01, 0.4)


func test_walls_block_movement() -> void:
	# Safe room north wall at z = 10: walk north from inside.
	var p := map.move_circle(Vector2(2, 11), Vector2(0, -3), 0.35)
	check(p.y > 10.15 + 0.34, "player stopped by safe room north wall, z=%f" % p.y)


func test_door_allows_movement() -> void:
	# West door of the safe room is centred at z = 14.
	var p := map.move_circle(Vector2(-3, 14), Vector2(-4, 0), 0.35)
	near(p.x, -7.0, 0.01, "player walks through the west door")


func test_no_tunnelling_at_high_speed() -> void:
	var p := map.move_circle(Vector2(2, 11), Vector2(0, -30), 0.35)
	check(p.y > 10.0, "fast mover does not tunnel")


func test_raycast_hits_wall() -> void:
	var t := map.raycast(Vector3(0, 1.6, 14), Vector3(0, 0, -1), 50.0)
	near(t, 14 - 10.15, 0.01, "ray hits north wall")


func test_low_prop_blocks_low_shots_only() -> void:
	# Lab bench top is 0.95 high at z in [-4,-3].
	var low := map.raycast(Vector3(-13, 0.5, 0), Vector3(0, 0, -1), 10.0)
	var high := map.raycast(Vector3(-13, 1.6, 0), Vector3(0, 0, -1), 10.0)
	near(low, 3.0, 0.01, "low ray hits bench")
	check(high > 5.0, "eye-level ray passes over bench")


func test_segment_clear() -> void:
	check(map.segment_clear(Vector2(-3, 14), Vector2(3, 14), 0.3), "clear inside safe room")
	check(not map.segment_clear(Vector2(0, 14), Vector2(0, 5), 0.3), "blocked by wall")
