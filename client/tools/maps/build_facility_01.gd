extends SceneTree
## Greybox generator for map "facility_01" (abandoned research facility).
##   godot --headless --path client --script res://tools/maps/build_facility_01.gd
## Writes res://scenes/maps/facility_01.tscn. While the map is greybox this
## script is the layout source. Once real art is placed in the scene in the
## editor, retire this script and edit the scene directly; the exporter
## (export_map.gd) only reads node groups, so it keeps working either way.
##
## Coordinates: sim plane = Godot (x, z), metres. North = -Z.

const OUT := "res://scenes/maps/facility_01.tscn"
const T := 0.3          # wall thickness
const H := 3.0          # wall height = floor height
const FENCE_H := 2.4

var _outdoor := false  ## while true, new boxes are tagged open-air (moonlight layer)
var map_root: Node3D
var geo: Node3D
var markers: Node3D
var lights: Node3D
var mats := {}


func _initialize() -> void:
	_make_materials()
	map_root = Node3D.new()
	map_root.name = "Facility01"
	map_root.set_meta("map_id", "facility_01")
	geo = _child(map_root, "Geometry")
	markers = _child(map_root, "Markers")
	lights = _child(map_root, "Lights")
	_environment()
	_floors()
	_wing_floors()
	_walls()
	_wing_walls()
	_props()
	_wing_props()
	_markers()
	_lights()
	_wing_lights()
	_fx()
	_wing_fx()
	var packed := PackedScene.new()
	var err := packed.pack(map_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("build_facility_01: ", "OK " + OUT if err == OK else "ERROR %d" % err)
	map_root.free()
	quit(0 if err == OK else 1)


# ---------------------------------------------------------------- layout

func _floors() -> void:
	var interior := [
		["SafeRoom", Rect2(-5, 10, 10, 8)],
		["RoomA_Lab", Rect2(-18, -6, 10, 8)],
		["RoomB_Storage", Rect2(8, -6, 10, 8)],
		["CorridorW_N", Rect2(-14, 2, 2, 11)],
		["CorridorW_S", Rect2(-14, 13, 9, 2)],
		["CorridorE_N", Rect2(12, 2, 2, 11)],
		["CorridorE_S", Rect2(5, 13, 9, 2)],
	]
	for f in interior:
		_floor(f[0], f[1], "floor_concrete")
		_box("Ceiling_" + f[0], Vector3(f[1].position.x, H, f[1].position.y), Vector3(f[1].end.x, H + 0.2, f[1].end.y), "ceiling", "map_visual")
	_floor("Yard", Rect2(-22, -24, 44, 18), "ground_yard")
	_floor("PadE1", Rect2(-11.5, -27, 3, 3), "ground_yard")
	_floor("PadE2", Rect2(8.5, -27, 3, 3), "ground_yard")
	_floor("PadE3", Rect2(-21, -3.5, 3, 3), "ground_yard")
	_floor("PadE4", Rect2(18, -3.5, 3, 3), "ground_yard")


func _walls() -> void:
	# Safe room (centre pieces + mirrored side walls)
	_hwall("SafeN", 10, -5, 5, [])
	_hwall("SafeS", 18, -5, 5, [[0.0, 2.5]])  # door to the old grounds (phase 10)
	_mirror_v("SafeSide", -5, 10, 18, [[14.0, 2.0]])
	# Corridors (west side, mirrored east)
	_mirror_h("CorrS", 15, -14, -5, [])
	_mirror_h("CorrN", 13, -12, -5, [])
	_mirror_v("CorrOuter", -14, 2, 15, [])
	_mirror_v("CorrInner", -12, 2, 13, [])
	# Rooms A / B
	_mirror_h("RoomSouth", 2, -18, -8, [[-13.0, 2.0]])
	_mirror_h("RoomNorth", -6, -18, -8, [[-13.0, 2.5]])
	_mirror_v("RoomOuter", -18, -6, 2, [[-2.0, 1.8]])
	_mirror_v("RoomInner", -8, -6, 2, [])
	_hwall("Facade", -6, -8, 8, [])
	# Yard fence
	_mirror_v("FenceSide", -22, -24, -6, [], FENCE_H, "fence")
	_mirror_h("FenceCorner", -6, -22, -18, [], FENCE_H, "fence")
	_hwall("FenceNorth", -24, -22, 22, [[-10.0, 2.0], [10.0, 2.0]], FENCE_H, "fence")
	# Zombie entry pads (walled so nothing walks off the map)
	_mirror_v("PadNw", -11.5, -27, -24, [], FENCE_H, "fence")
	_mirror_v("PadNe", -8.5, -27, -24, [], FENCE_H, "fence")
	_mirror_h("PadNn", -27, -11.5, -8.5, [], FENCE_H, "fence")
	_mirror_h("PadWs", -3.5, -21, -18, [], H)
	_mirror_h("PadWn", -0.5, -21, -18, [], H)
	_mirror_v("PadWw", -21, -3.5, -0.5, [], H)


func _props() -> void:
	# Gameplay blockers (exported). Ones dressed with art props are hidden boxes.
	# name, min (x,y,z), max (x,y,z), material, visible
	var blockers := [
		["CrateStack", Vector3(-5.6, 0, -14.6), Vector3(-4.4, 1.0, -13.4), "crate", false],
		["CrateRow", Vector3(4.8, 0, -17.6), Vector3(7.2, 1.1, -16.4), "crate", false],
		["Container", Vector3(-2.5, 0, -12.1), Vector3(2.5, 2.4, -9.9), "container", true],
		["Barrier", Vector3(-14.3, 0, -18.5), Vector3(-13.7, 1.0, -15.5), "hazard", true],
		["Barrier2", Vector3(13.7, 0, -20.5), Vector3(14.3, 1.0, -17.5), "hazard", true],
		["LabBench", Vector3(-15, 0, -4.0), Vector3(-11, 0.95, -3.0), "metal", false],
		["Shelving", Vector3(11, 0, -4.0), Vector3(15, 2.2, -3.2), "metal", false],
		["AmmoCrate", Vector3(-0.6, 0, 10.15), Vector3(0.6, 0.8, 10.75), "ammo", false],
	]
	for p in blockers:
		var b := _box(p[0], p[1], p[2], p[3], "map_wall")
		b.visible = p[4]
	# --- art props: name, position, yaw [, blocker size (x, z), height]
	var items := [
		# safe room: lockers, terminal, ammo crate
		["Lockers", Vector3(-3.2, 0, 17.55), 0.0, Vector2(1.56, 0.52), 1.9],
		["Console", Vector3(3.2, 0, 17.5), 0.0, Vector2(0.95, 0.6), 1.3],
		["Crate", Vector3(0, 0, 10.45), 0.0],
		# lab: specimen tanks, benches, terminal, crystal growth
		["Tank", Vector3(-16.6, 0, -5.3), 0.0, Vector2(1.0, 1.0), 2.4],
		["Tank", Vector3(-9.5, 0, -5.3), 0.0, Vector2(1.0, 1.0), 2.4],
		["LabTable", Vector3(-14.05, 0, -3.5), 0.0],
		["LabTable", Vector3(-11.95, 0, -3.5), PI],
		["Console", Vector3(-17.5, 0, 0.9), -PI / 2, Vector2(0.6, 0.95), 1.3],
		["CrystalsSmall", Vector3(-9.0, 0, 1.2), 0.6],
		# storage: shelving, crates, barrels
		["Shelf", Vector3(12, 0, -3.6), 0.0],
		["Shelf", Vector3(14, 0, -3.6), PI],
		["Crate", Vector3(9.2, 0, -5.2), 0.0, Vector2(1.0, 0.6), 1.2],
		["Crate", Vector3(9.2, 0.6, -5.2), 0.3],
		["Barrel", Vector3(9.0, 0, 1.4), 0.0, Vector2(1.4, 0.85), 0.9],
		["Barrel", Vector3(9.65, 0, 1.45), 1.2],
		# corridors: rubble only, they must stay clear
		["Rubble", Vector3(-12.7, 0, 8.0), 0.8],
		["Rubble", Vector3(12.7, 0, 4.0), 2.2],
		# yard: outbreak crystals, posts, generator, barricades, barrels, crates
		["Crystals", Vector3(-7.5, 0, -20.0), 0.4, Vector2(1.6, 1.6), 2.0],
		["CrystalsSmall", Vector3(6.6, 0, -8.2), 1.0],
		["CrystalsSmall", Vector3(15.5, 0, -22.6), 2.0],
		["CrystalsSmall", Vector3(-18.5, 0, -8.6), 3.0],
		["GothicLamp", Vector3(-15, 0, -7.2), 0.0, Vector2(0.45, 0.45), 4.0],
		["GothicLamp", Vector3(15, 0, -7.2), 0.0, Vector2(0.45, 0.45), 4.0],
		["Generator", Vector3(17.5, 0, -12.5), PI / 2, Vector2(1.0, 1.7), 1.2],
		["Sandbags", Vector3(-13.5, 0, -21.5), 0.0, Vector2(2.1, 0.55), 0.7],
		["Sandbags", Vector3(13.5, 0, -21.5), 0.0, Vector2(2.1, 0.55), 0.7],
		["BarrelChem", Vector3(-19.5, 0, -16.0), 0.0, Vector2(1.5, 1.3), 0.9],
		["BarrelChem", Vector3(-18.9, 0, -15.4), 0.7],
		["BarrelChem", Vector3(19.3, 0, -19.5), 0.0, Vector2(0.7, 0.7), 0.9],
		["Barrel", Vector3(3.3, 0, -12.6), 0.0, Vector2(1.3, 1.3), 0.9],
		["Barrel", Vector3(3.9, 0, -12.0), 2.0],
		["Crate", Vector3(-5.0, 0, -14.25), 0.0],
		["Crate", Vector3(-5.0, 0, -13.75), 0.0],
		["Crate", Vector3(-5.0, 0.6, -14.0), PI / 2],
		["Crate", Vector3(5.5, 0, -17.3), 0.0],
		["Crate", Vector3(6.6, 0, -17.3), 0.0],
		["Crate", Vector3(5.5, 0, -16.7), 0.0],
		["Crate", Vector3(6.6, 0, -16.7), 0.0],
		["Crate", Vector3(6.0, 0.6, -17.0), 0.15],
		["Brazier", Vector3(-4.6, 0, -7.6), 0.3, Vector2(0.8, 0.8), 1.1],   # fire fx on top
		["Brazier", Vector3(4.6, 0, -7.6), 1.9, Vector2(0.8, 0.8), 1.1],
		["Rubble", Vector3(-3.0, 0, -21.0), 1.3],
		["Rubble", Vector3(10.0, 0, -9.0), 0.2],
		# dark fantasy: gothic gates, a small graveyard, dead trees, the fallen
		["GothicArch", Vector3(-10, 0, -24.0), PI],
		["GothicArch", Vector3(10, 0, -24.0), PI],
		["DeadTree", Vector3(-20.3, 0, -22.4), 0.7, Vector2(0.6, 0.6), 3.0],
		["DeadTree", Vector3(20.2, 0, -22.6), 2.6, Vector2(0.6, 0.6), 3.0],
		["DeadTree", Vector3(-20.6, 0, -12.6), 4.1, Vector2(0.6, 0.6), 3.0],
		["Tombstone", Vector3(20.8, 0, -8.6), PI / 2, Vector2(0.35, 0.8), 0.9],
		["Tombstone", Vector3(20.8, 0, -10.4), PI / 2 + 0.15, Vector2(0.35, 0.8), 0.9],
		["TombstoneTall", Vector3(20.6, 0, -16.0), PI / 2, Vector2(0.75, 0.75), 1.9],
		["Tombstone", Vector3(-20.8, 0, -10.0), -PI / 2, Vector2(0.35, 0.8), 0.9],
		["TombstoneTall", Vector3(-20.6, 0, -19.4), -PI / 2, Vector2(0.75, 0.75), 1.9],
		["SkeletonSit", Vector3(-1.6, 0, -6.4), 0.0, Vector2(0.6, 0.9), 0.8],
		["SkeletonSit", Vector3(21.55, 0, -13.4), PI / 2, Vector2(0.9, 0.6), 0.8],
		["SkeletonSit", Vector3(17.6, 0, -5.4), PI / 2 + 0.3, Vector2(0.9, 0.6), 0.8],
		["Bones", Vector3(-4.6, 0, -17.2), 0.4],
		["Bones", Vector3(-11.4, 0, -19.4), 2.0],
		["Bones", Vector3(20.6, 0, -12.2), 1.0],
		["Candles", Vector3(-1.1, 0, -6.55), 0.0],
		["Candles", Vector3(20.8, 0, -9.5), 0.0],
		["Candles", Vector3(-4.4, 0, 10.5), 0.0],
		["Candles", Vector3(4.4, 0, 10.5), 1.0],
		["Candles", Vector3(-11.4, 0.95, -3.4), 0.5],
		["Banner", Vector3(-6.5, 0.3, -6.2), 0.0],
		["Banner", Vector3(6.5, 0.3, -6.2), 0.0],
	]
	for it in items:
		_prop(it[0], it[1], it[2])
		if it.size() >= 5:
			var sz: Vector2 = it[3]
			var c: Vector3 = it[1]
			var blk := _box("Block_" + it[0], Vector3(c.x - sz.x / 2, 0, c.z - sz.y / 2), Vector3(c.x + sz.x / 2, it[4], c.z + sz.y / 2), "metal", "map_wall")
			blk.visible = false
	# wrought-iron spikes along the yard fence tops (gates left open)
	for x in range(-21, 22, 2):
		if absi(x - 10) > 2 and absi(x + 10) > 2:
			_prop("SpikeRow", Vector3(x, FENCE_H, -24.0), 0.0)
	for z in range(-23, -6, 2):
		_prop("SpikeRow", Vector3(-22.0, FENCE_H, z), PI / 2)
		_prop("SpikeRow", Vector3(22.0, FENCE_H, z), PI / 2)
	# pipes along the corridor walls, just under the ceiling
	for z in [3.0, 5.0, 7.0, 9.0, 11.0]:
		_prop("Pipe", Vector3(-13.68, 2.72, z), -PI / 2)
		_prop("Pipe", Vector3(13.68, 2.72, z), PI / 2)


## Art prop marker; the game instantiates the mesh from env_props.glb (MapDecor).
func _prop(prop_name: String, pos: Vector3, yaw: float) -> void:
	var m := Marker3D.new()
	m.name = "Prop_%s_%d" % [prop_name, markers.get_child_count()]
	m.position = pos
	m.rotation.y = yaw
	m.set_meta("prop", prop_name)
	m.add_to_group("map_prop", true)
	_add(markers, m)


func _markers() -> void:
	var spawns := [Vector2(-1.5, 15.5), Vector2(1.5, 15.5), Vector2(-1.5, 17.0), Vector2(1.5, 17.0), Vector2(0.0, 13.8)]
	for i in spawns.size():
		var m := _marker("PlayerSpawn%d" % (i + 1), spawns[i], "map_player_spawn")
		m.rotation.y = 0.0
	var entries := [
		["yard_nw", Vector2(-10, -25.8), Vector2(-10, -22.5)],
		["yard_ne", Vector2(10, -25.8), Vector2(10, -22.5)],
		["lab_window", Vector2(-19.8, -2), Vector2(-16.5, -2)],
		["storage_window", Vector2(19.8, -2), Vector2(16.5, -2)],
		# the old grounds (phase 10): crypt and chapel gates, the catacomb mouth
		["crypt_gate", Vector2(-31.5, 25.0), Vector2(-28.5, 25.0)],
		["chapel_gate", Vector2(31.5, 25.0), Vector2(28.5, 25.0)],
		["catacomb_gate", Vector2(0.0, 44.8), Vector2(0.0, 41.8)],
	]
	for e in entries:
		var m := _marker("ZombieEntry_" + e[0], e[1], "map_zombie_entry")
		m.set_meta("entry_id", e[0])
		m.set_meta("inside", e[2])
	var buy := _marker("Buy_rifle", Vector2(-8.6, -2.0), "map_interact")
	buy.set_meta("interact_id", "buy_rifle")
	buy.set_meta("kind", "weapon")
	buy.set_meta("item", "rifle")
	buy.set_meta("radius", 1.8)
	_box("BuyPanel_rifle", Vector3(-8.2, 1.0, -2.8), Vector3(-8.12, 1.9, -1.2), "panel_buy", "map_visual")
	_label("BuyLabel_rifle", Vector3(-8.25, 2.15, -2.0), "AR-7 CARBINE", -PI / 2)
	var ammo := _marker("Ammo", Vector2(0, 11.3), "map_interact")
	ammo.set_meta("interact_id", "ammo_safe")
	ammo.set_meta("kind", "ammo")
	ammo.set_meta("radius", 1.8)
	_label("AmmoLabel", Vector3(0, 1.25, 10.5), "AMMO", 0.0)
	# Supply cache (random weapon box) in the storage room; the visible model is
	# spawned by the game (BoxView), this hidden box only blocks movement.
	var box_block := _box("SupplyBox_block", Vector3(15.8, 0, 1.05), Vector3(17.2, 0.8, 1.75), "crate", "map_wall")
	box_block.visible = false
	var box := _marker("SupplyBox", Vector2(16.5, 0.2), "map_interact")
	box.set_meta("interact_id", "box_storage")
	box.set_meta("kind", "box")
	box.set_meta("radius", 1.9)
	# wall-buys in the old grounds: SMG in the catacomb, shotgun in the chapel
	var buy_smg := _marker("Buy_smg", Vector2(2.3, 36.0), "map_interact")
	buy_smg.set_meta("interact_id", "buy_smg")
	buy_smg.set_meta("kind", "weapon")
	buy_smg.set_meta("item", "smg")
	buy_smg.set_meta("radius", 1.8)
	_box("BuyPanel_smg", Vector3(2.75, 1.0, 35.2), Vector3(2.85, 1.9, 36.8), "panel_buy", "map_visual")
	_label("BuyLabel_smg", Vector3(2.7, 2.15, 36.0), "VX-9 RIPPER", -PI / 2)
	var buy_sg := _marker("Buy_shotgun", Vector2(23.0, 19.3), "map_interact")
	buy_sg.set_meta("interact_id", "buy_shotgun")
	buy_sg.set_meta("kind", "weapon")
	buy_sg.set_meta("item", "shotgun")
	buy_sg.set_meta("radius", 1.8)
	_box("BuyPanel_shotgun", Vector3(22.2, 1.0, SOUTH + 0.16), Vector3(23.8, 1.9, SOUTH + 0.26), "panel_buy", "map_visual")
	_label("BuyLabel_shotgun", Vector3(23.0, 2.15, SOUTH + 0.3), "KS-12 BREACHER", 0.0)
	# Perk machines (phase 8): the visible machine is spawned by the game
	# (PerkMachineView); the hidden box only blocks movement.
	# yaw turns the machine's front (local -Z) towards the room: -PI/2 faces +X.
	for pm in [["ironhide", Vector2(-4.5, 12.4), -PI / 2], ["quickhands", Vector2(-17.5, 0.6), -PI / 2],
			["longstride", Vector2(8.5, -4.6), -PI / 2], ["switchblade", Vector2(21.5, -15.0), PI / 2]]:
		var c: Vector2 = pm[1]
		var along := Vector2(0.45, 0.4) if pm[2] == 0.0 else Vector2(0.45, 0.4)
		var blk := _box("PerkMachine_block_" + pm[0], Vector3(c.x - along.x, 0, c.y - along.y), Vector3(c.x + along.x, 2.0, c.y + along.y), "crate", "map_wall")
		blk.visible = false
		var mk := _marker("Perk_" + pm[0], c, "map_interact")
		mk.set_meta("interact_id", "perk_" + pm[0])
		mk.set_meta("kind", "perk")
		mk.set_meta("item", pm[0])
		mk.set_meta("radius", 1.8)
		mk.set_meta("yaw", pm[2])
	var safe := _marker("SafeArea", Vector2(0, 14), "map_safe_area")
	safe.set_meta("min", Vector2(-5, 10))
	safe.set_meta("max", Vector2(5, 18))


## Lighting: readable and fairly bright, with a dark-fantasy palette —
## warm gold for safety, teal/amber in the halls, cold labs, violet outbreak.
const WARM := Color(1.0, 0.86, 0.62)
const AMBER := Color(1.0, 0.62, 0.3)
const TEAL := Color(0.25, 0.95, 0.88)
const VIOLET := Color(0.68, 0.36, 1.0)
const COOL := Color(0.82, 0.9, 1.0)


const MOON_DIR := Vector3(-0.33, 0.36, -0.87)  # towards the moon: low in the north-west, behind the castle


func _lights() -> void:
	# safe room: two ceiling fixtures, warm and inviting
	for z in [12.6, 15.6]:
		_prop("CeilingLamp", Vector3(0, H, z), 0.0)
		_omni("SafeLight%d" % int(z), Vector3(0, 2.7, z), WARM, 1.7, 8.5)
	# corridors: wall lamps alternating teal and amber
	var halls := [
		[Vector3(-13.85, 2.3, 5.0), -PI / 2, "Teal", TEAL], [Vector3(-13.85, 2.3, 10.5), -PI / 2, "Warm", AMBER],
		[Vector3(-9.0, 2.3, 14.85), 0.0, "Warm", AMBER], [Vector3(13.85, 2.3, 5.0), PI / 2, "Warm", AMBER],
		[Vector3(13.85, 2.3, 10.5), PI / 2, "Teal", TEAL], [Vector3(9.0, 2.3, 14.85), 0.0, "Teal", TEAL],
	]
	for i in halls.size():
		var hl: Array = halls[i]
		_prop("WallLamp" + hl[2], hl[0], hl[1])
		var out := Vector3(-sin(hl[1]), 0, -cos(hl[1])) * 0.45
		_omni("Hall%d" % i, hl[0] + out, hl[3], 1.5, 6.5)
	# lab: cold overhead light, teal tanks, violet crystal
	_prop("CeilingLamp", Vector3(-13, H, -1.5), PI / 2)
	_omni("LabLight", Vector3(-13, 2.7, -1.5), COOL, 1.5, 9.5)
	_omni("TankA", Vector3(-16.6, 1.3, -4.6), TEAL, 1.4, 5.5)
	_omni("TankB", Vector3(-9.5, 1.3, -4.6), TEAL, 1.4, 5.5, true)
	_omni("LabCrystal", Vector3(-9.0, 0.7, 1.0), VIOLET, 0.9, 3.5, true)
	# storage: two warm overheads
	for x in [11.0, 15.0]:
		_prop("CeilingLamp", Vector3(x, H, -2.0), PI / 2)
		_omni("Store%d" % int(x), Vector3(x, 2.7, -2.0), Color(1.0, 0.78, 0.5), 1.5, 8.0)
	# yard: violet outbreak glow, sodium lamp posts, cold moon
	_omni("Breach", Vector3(-7.5, 1.6, -20.0), Color(0.85, 0.35, 1.0), 3.2, 13.0)
	lights.get_node("Breach").set_meta("flicker", "pulse")
	_omni("PostW", Vector3(-15, 3.3, -7.82), Color(0.62, 0.74, 1.0), 3.0, 15.0)
	_omni("PostE", Vector3(15, 3.3, -7.82), Color(0.62, 0.74, 1.0), 3.0, 15.0)
	_omni("YardFill", Vector3(0, 4.0, -15.0), Color(0.55, 0.62, 0.95), 1.6, 16.0)
	_omni("GenLight", Vector3(16.9, 0.9, -12.5), Color(1.0, 0.25, 0.2), 0.7, 3.0, true)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.68, 0.64, 0.98)
	moon.light_energy = 1.0
	moon.basis = Basis.looking_at(-MOON_DIR)  # shines from the moon drawn by the sky shader
	moon.shadow_enabled = false
	moon.light_cull_mask = 2  # outdoor layer only (MapBatcher puts yard meshes on layer 2)
	_add(lights, moon)


func _environment() -> void:
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_night.gdshader")
	sky_mat.set_shader_parameter("moon_dir", MOON_DIR.normalized())
	sky_mat.set_shader_parameter("moon_disc", 0.0)  # the moon face billboard (fx "moon") replaces it
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.57, 0.72)
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_light_color = Color(0.24, 0.15, 0.34)
	env.fog_density = 0.009
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.07
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(map_root, we)


# ---------------------------------------------------------------- atmosphere

const ARCANE := Color(0.72, 0.35, 1.0)
const ICHOR := Color(1.0, 0.3, 0.8)


## Dark-fantasy effect markers (group `map_fx`), built at runtime by Atmosphere.
## Visual only: not exported to shared/maps.
func _fx() -> void:
	var floor_rot := Vector3(-PI / 2, 0, 0)
	_fxm("motes", Vector3(0, 1.4, 14.0), Vector3.ZERO, {"extents": Vector3(4.2, 1.2, 3.4), "amount": 18, "color": Color(1.0, 0.78, 0.4)})
	# the outbreak: a floating rift crystal over the yard breach
	_fxm("rift", Vector3(-7.5, 3.0, -20.0), Vector3.ZERO, {"color": ICHOR})
	# corruption veins creeping from the windows and over the facade
	for side in [-1.0, 1.0]:
		var face := Vector3(0, -side * PI / 2, 0)  # west wall faces +X, east wall faces -X
		for z in [-3.7, -0.3]:
			_fxm("sigil", Vector3(side * 17.83, 1.25, z), face, {"tex": "veins", "size": Vector2(1.9, 2.5), "color": ARCANE, "energy": 1.2, "pulse": 0.35})
		_fxm("sigil", Vector3(side * 4.2, 1.45, -6.17), Vector3(0, PI, 0), {"tex": "veins", "size": Vector2(3.2, 2.9), "color": ICHOR, "energy": 1.0, "pulse": 0.3})
	# lab and storage: drifting dust
	_fxm("motes", Vector3(-13, 1.5, -2.0), Vector3.ZERO, {"extents": Vector3(4.5, 1.2, 3.5), "amount": 22, "color": Color(0.45, 0.9, 1.0)})
	_fxm("motes", Vector3(13, 1.5, -2.0), Vector3.ZERO, {"extents": Vector3(4.5, 1.2, 3.5), "amount": 14, "color": Color(1.0, 0.7, 0.45)})
	# yard: violet spores, ground mist, burn barrels
	_fxm("motes", Vector3(0, 2.2, -15.0), Vector3.ZERO, {"extents": Vector3(20.0, 2.0, 8.5), "amount": 70, "color": Color(0.8, 0.45, 1.0)})
	_fxm("mist", Vector3(0, 0.18, -15.0), floor_rot, {"size": Vector2(44, 18), "color": Color(0.42, 0.3, 0.62, 0.3), "speed": 1.0})
	_fxm("mist", Vector3(0, 0.55, -15.0), floor_rot, {"size": Vector2(44, 18), "color": Color(0.5, 0.36, 0.7, 0.14), "speed": 1.6})
	for x in [-4.6, 4.6]:
		_fxm("fire", Vector3(x, 1.0, -7.6), Vector3.ZERO, {"energy": 2.0, "range": 7.0})
	# candle lights (the candle meshes are props)
	for p in [Vector3(-1.1, 0.5, -6.6), Vector3(20.6, 0.5, -9.5), Vector3(-4.4, 0.5, 10.7), Vector3(4.4, 0.5, 10.7)]:
		_fxm("candle", p, Vector3.ZERO, {"energy": 0.8, "range": 3.2})
	# hellfire fissures creeping from the breach
	for f in [[Vector3(-7.5, 0.04, -15.6), 0.4, Vector2(2.6, 4.2)], [Vector3(-3.6, 0.04, -20.6), -1.3, Vector2(2.4, 3.6)], [Vector3(-11.2, 0.04, -17.0), 2.2, Vector2(2.2, 3.2)]]:
		_fxm("sigil", f[0], Vector3(-PI / 2, f[1], 0), {"tex": "veins", "size": f[2], "color": Color(1.0, 0.32, 0.08), "energy": 1.7, "pulse": 0.35})
	# the world beyond the fence: mountains, castles, a forest, the moon and a storm
	_fxm("backdrop", Vector3(0, -2.0, 0), Vector3.ZERO, {"node": "Mountains"})
	_fxm("backdrop", Vector3(-62, -3.0, -178), Vector3(0, PI + 0.25, 0), {"node": "CastleHill"})
	_fxm("backdrop", Vector3(80, -4.0, -195), Vector3(0, PI - 0.35, 0), {"node": "GiantHand"})
	_fxm("forest", Vector3.ZERO, Vector3.ZERO, {"count": 340, "r_min": 54.0, "r_max": 150.0, "seed": 5})
	_fxm("moon", MOON_DIR.normalized() * 450.0, Vector3.ZERO, {"size": 110.0, "energy": 1.35})
	_fxm("storm", Vector3.ZERO, Vector3.ZERO, {"radius": 230.0})
	# light shafts under the ceiling lamps
	for p in [Vector3(0, H - 0.05, 12.6), Vector3(0, H - 0.05, 15.6)]:
		_fxm("shaft", p, Vector3.ZERO, {"color": WARM, "energy": 0.16})
	_fxm("shaft", Vector3(-13, H - 0.05, -1.5), Vector3.ZERO, {"color": COOL, "energy": 0.14})
	for x in [11.0, 15.0]:
		_fxm("shaft", Vector3(x, H - 0.05, -2.0), Vector3.ZERO, {"color": Color(1.0, 0.78, 0.5), "energy": 0.14})


func _fxm(kind: String, pos: Vector3, rot: Vector3, params: Dictionary) -> void:
	var m := Marker3D.new()
	m.name = "Fx_%s_%d" % [kind, markers.get_child_count()]
	m.position = pos
	m.rotation = rot
	m.set_meta("fx", kind)
	for k in params:
		m.set_meta(k, params[k])
	m.add_to_group("map_fx", true)
	_add(markers, m)


# ---------------------------------------------------------------- helpers

func _hwall(name: String, z: float, x0: float, x1: float, gaps: Array, h := H, mat := "wall") -> void:
	for seg in _split(x0, x1, gaps):
		_box("%s_%d" % [name, geo.get_child_count()], Vector3(seg.x - T / 2, 0, z - T / 2), Vector3(seg.y + T / 2, h, z + T / 2), mat, "map_wall")
		_dress(seg.x - T / 2, seg.y + T / 2, z, false, h, mat)
	if h == H and mat == "wall":
		for g in gaps:
			_prop("DoorFrame25" if g[1] > 2.2 else "DoorFrame2", Vector3(g[0], 0, z), 0.0)
	elif mat == "stone_wall":
		for g in gaps:
			_prop("GothicArch", Vector3(g[0], 0, z), 0.0)


func _vwall(name: String, x: float, z0: float, z1: float, gaps: Array, h := H, mat := "wall") -> void:
	for seg in _split(z0, z1, gaps):
		_box("%s_%d" % [name, geo.get_child_count()], Vector3(x - T / 2, 0, seg.x - T / 2), Vector3(x + T / 2, h, seg.y + T / 2), mat, "map_wall")
		_dress(seg.x - T / 2, seg.y + T / 2, x, true, h, mat)
	if h == H and mat == "wall":
		for g in gaps:
			_prop("DoorFrame25" if g[1] > 2.2 else "DoorFrame2", Vector3(x, 0, g[0]), PI / 2)
	elif mat == "stone_wall":
		for g in gaps:
			_prop("GothicArch", Vector3(x, 0, g[0]), PI / 2)


## Visual wall dressing (no collision): baseboard, cornice and pillars on both
## faces of interior walls; posts on fences. `vertical` = wall runs along Z.
func _dress(a: float, b: float, at: float, vertical: bool, h: float, mat: String) -> void:
	var boxes := []
	if mat in ["wall", "stone_wall"] and h == H:
		boxes.append([a, b, 0.0, 0.22, T / 2 + 0.03, "trim"])
		boxes.append([a, b, H - 0.18, H, T / 2 + 0.05, "trim"])
		var n := int((b - a) / 3.0)
		for i in range(1, n + 1):
			var c := a + (b - a) * i / (n + 1)
			boxes.append([c - 0.13, c + 0.13, 0.0, H, T / 2 + 0.06, "pillar"])
	elif mat == "fence":
		var n := int((b - a) / 2.5)
		for i in range(0, n + 2):
			var c := clampf(a + (b - a) * i / (n + 1), a + 0.1, b - 0.1)
			boxes.append([c - 0.1, c + 0.1, 0.0, h + 0.2, T / 2 + 0.05, "pillar"])
	for bx in boxes:
		var mn: Vector3
		var mx: Vector3
		if vertical:
			mn = Vector3(at - bx[4], bx[2], bx[0])
			mx = Vector3(at + bx[4], bx[3], bx[1])
		else:
			mn = Vector3(bx[0], bx[2], at - bx[4])
			mx = Vector3(bx[1], bx[3], at + bx[4])
		_box("Dress_%d" % geo.get_child_count(), mn, mx, bx[5], "map_visual")


func _mirror_h(name: String, z: float, x0: float, x1: float, gaps: Array, h := H, mat := "wall") -> void:
	_hwall(name + "W", z, x0, x1, gaps, h, mat)
	var mg := []
	for g in gaps:
		mg.append([-g[0], g[1]])
	_hwall(name + "E", z, -x1, -x0, mg, h, mat)


func _mirror_v(name: String, x: float, z0: float, z1: float, gaps: Array, h := H, mat := "wall") -> void:
	_vwall(name + "W", x, z0, z1, gaps, h, mat)
	_vwall(name + "E", -x, z0, z1, gaps, h, mat)


## Splits [a, b] into solid segments around [center, width] gaps.
func _split(a: float, b: float, gaps: Array) -> Array:
	var segs := []
	var cur := a
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	for g in sorted:
		var g0: float = g[0] - g[1] / 2.0
		var g1: float = g[0] + g[1] / 2.0
		if g0 > cur:
			segs.append(Vector2(cur, g0))
		cur = g1
	if cur < b:
		segs.append(Vector2(cur, b))
	return segs


func _floor(name: String, r: Rect2, mat: String, outdoor := false) -> void:
	var f := _box("Floor_" + name, Vector3(r.position.x, -0.2, r.position.y), Vector3(r.end.x, 0, r.end.y), mat, "map_floor")
	if outdoor:
		f.set_meta("outdoor", true)


func _box(name: String, mn: Vector3, mx: Vector3, mat: String, group: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var mesh := BoxMesh.new()
	mesh.size = mx - mn
	mi.mesh = mesh
	mi.material_override = mats[mat]
	mi.position = (mn + mx) / 2.0
	mi.add_to_group(group, true)
	if _outdoor:
		mi.set_meta("outdoor", true)  # moonlit layer (MapBatcher)
	_add(geo, mi)
	return mi


func _marker(name: String, p: Vector2, group: String) -> Marker3D:
	var m := Marker3D.new()
	m.name = name
	m.position = Vector3(p.x, 0, p.y)
	m.add_to_group(group, true)
	_add(markers, m)
	return m


func _label(name: String, pos: Vector3, text: String, yaw: float) -> void:
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.position = pos
	l.rotation.y = yaw
	l.font_size = 48
	l.pixel_size = 0.004
	l.modulate = Color(0.95, 0.85, 0.4)
	l.outline_size = 8
	_add(geo, l)


func _omni(name: String, pos: Vector3, color: Color, energy: float, rng: float, extra := false) -> void:
	var o := OmniLight3D.new()
	o.name = name
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.shadow_enabled = false
	o.add_to_group("map_light", true)
	if extra:
		o.add_to_group("map_light_extra", true)  # switched off on low quality
	_add(lights, o)


func _child(parent: Node, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	_add(parent, n)
	return n


func _add(parent: Node, n: Node) -> void:
	parent.add_child(n)
	n.owner = map_root


func _make_materials() -> void:
	var grime: Texture2D = load("res://assets/textures/grime.png")
	var hazard: Texture2D = load("res://assets/textures/hazard.png")
	# name: [albedo tint, texture base name or null, triplanar scale, metallic]
	var defs := {
		"wall": [Color(1, 1, 1), "wall_panels", 1.0 / 3.0, 0.0],
		"floor_concrete": [Color(1, 1, 1), "floor_tiles", 0.25, 0.0],
		"ceiling": [Color(1, 1, 1), "ceiling", 0.42, 0.0],
		"ground_yard": [Color(1, 1, 1), "ground", 0.18, 0.0],
		"fence": [Color(0.85, 0.85, 0.9), "metal_plate", 0.5, 0.4],
		"trim": [Color(0.55, 0.55, 0.6), "metal_plate", 1.0, 0.5],
		"pillar": [Color(0.72, 0.74, 0.82), "metal_plate", 0.5, 0.4],
		"container": [Color(0.5, 0.78, 0.8), "metal_plate", 0.5, 0.3],
		"crate": [Color(0.42, 0.33, 0.2), grime, 0.8, 0.0],
		"metal": [Color(0.42, 0.44, 0.46), grime, 0.7, 0.0],
		"hazard": [Color(1, 1, 1), hazard, 0.5, 0.0],
		"ammo": [Color(0.25, 0.32, 0.18), grime, 1.0, 0.0],
		"panel_buy": [Color(0.9, 0.7, 0.2), null, 1.0, 0.0],
		# the old grounds (phase 10): dressed stone, flagstones, crypt floor
		"stone_wall": [Color(1, 1, 1), "stone_blocks", 0.5, 0.0],
		"floor_cloister": [Color(0.78, 0.78, 0.84), "floor_tiles", 0.3, 0.0],
		"floor_crypt": [Color(0.62, 0.6, 0.66), "stone_blocks", 0.33, 0.0],
	}
	for k in defs:
		var d: Array = defs[k]
		var m := StandardMaterial3D.new()
		m.resource_name = k
		m.albedo_color = d[0]
		m.roughness = 0.85
		m.metallic = d[3]
		if d[1] is String:
			m.albedo_texture = load("res://assets/textures/%s_albedo.png" % d[1])
			m.normal_enabled = true
			m.normal_texture = load("res://assets/textures/%s_normal.png" % d[1])
			m.normal_scale = 1.0
		elif d[1] != null:
			m.albedo_texture = d[1]
		if d[1] != null:
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * d[2]
		if k == "panel_buy":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.65, 0.15)
			m.emission_energy_multiplier = 1.4
		mats[k] = m


# ---------------------------------------------------------------- the old grounds (phase 10)
# South of the safe room: a walled graveyard cloister, a crypt to the west, a
# chapel to the east and a catacomb tunnel to a southern gate. Doubles the
# playable area; three more zombie entries; two wall-buys.

const SOUTH := 18.3   # north edge of the cloister
const S_END := 32.3   # south edge of the cloister, crypt and chapel
const CAT_END := 43.3 # south end of the catacomb


func _wing_floors() -> void:
	# the floor starts at the safe room's wall line, so the door strip is walkable
	_floor("Cloister", Rect2(-16, 18.0, 32, S_END - 18.0), "floor_cloister", true)
	for f in [["Crypt", Rect2(-30, SOUTH, 14, S_END - SOUTH)], ["Chapel", Rect2(16, SOUTH, 14, S_END - SOUTH)],
			["Catacomb", Rect2(-3, S_END, 6, CAT_END - S_END)]]:
		_floor(f[0], f[1], "floor_crypt")
		_box("Ceiling_" + f[0], Vector3(f[1].position.x, H, f[1].position.y), Vector3(f[1].end.x, H + 0.2, f[1].end.y), "stone_wall", "map_visual")
	_outdoor = true
	_floor("PadCrypt", Rect2(-33, 23.5, 3, 3), "ground_yard", true)
	_floor("PadChapel", Rect2(30, 23.5, 3, 3), "ground_yard", true)
	_floor("PadCatacomb", Rect2(-1.5, CAT_END, 3, 3), "ground_yard", true)
	_outdoor = false


func _wing_walls() -> void:
	_outdoor = true
	# cloister: iron fence beside the safe room, stone walls with arched doors
	_mirror_h("CloisterN", SOUTH, -16, -5, [], FENCE_H, "fence")
	_mirror_v("CloisterSide", -16, SOUTH, S_END, [[25.3, 2.5]], H, "stone_wall")
	_hwall("CloisterS", S_END, -16, 16, [[0.0, 2.5]], H, "stone_wall")
	_outdoor = false
	# crypt (west) and chapel (east), mirrored, each with a gate for the dead
	_mirror_h("WingN", SOUTH, -30, -16, [], H, "stone_wall")
	_mirror_h("WingS", S_END, -30, -16, [], H, "stone_wall")
	_mirror_v("WingOuter", -30, SOUTH, S_END, [[25.0, 2.5]], H, "stone_wall")
	# catacomb tunnel to the southern gate
	_mirror_v("CatacombSide", -3, S_END, CAT_END, [], H, "stone_wall")
	_hwall("CatacombS", CAT_END, -3, 3, [[0.0, 2.5]], H, "stone_wall")
	# entry pads (fenced so nothing walks off the map)
	_outdoor = true
	_mirror_h("PadWingN", 23.5, -33, -30, [], FENCE_H, "fence")
	_mirror_h("PadWingS", 26.5, -33, -30, [], FENCE_H, "fence")
	_mirror_v("PadWingW", -33, 23.5, 26.5, [], FENCE_H, "fence")
	_mirror_v("PadCatacomb", -1.5, CAT_END, CAT_END + 3, [], FENCE_H, "fence")
	_hwall("PadCatacombS", CAT_END + 3, -1.5, 1.5, [], FENCE_H, "fence")
	_outdoor = false


func _wing_props() -> void:
	var items := [
		# cloister: the monument, lamps, dead trees, braziers, a gibbet, grave rows
		["Obelisk", Vector3(0, 0, 25.3), 0.0, Vector2(1.3, 1.3), 3.8],
		["GothicLamp", Vector3(-12.0, 0, 20.5), 0.0, Vector2(0.45, 0.45), 4.0],
		["GothicLamp", Vector3(12.0, 0, 30.1), 0.0, Vector2(0.45, 0.45), 4.0],
		["DeadTree", Vector3(-14.3, 0, 30.7), 1.1, Vector2(0.6, 0.6), 3.0],
		["DeadTree", Vector3(14.2, 0, 20.2), 2.9, Vector2(0.6, 0.6), 3.0],
		["Brazier", Vector3(-3.4, 0, 20.4), 0.5, Vector2(0.8, 0.8), 1.1],
		["Brazier", Vector3(3.4, 0, 30.2), 1.7, Vector2(0.8, 0.8), 1.1],
		["Gibbet", Vector3(10.6, 0, 23.6), -PI / 2, Vector2(0.5, 0.5), 3.5],
		["SkeletonSit", Vector3(-15.4, 0, 21.2), PI / 2, Vector2(0.6, 0.9), 0.8],
		["Bones", Vector3(-7.4, 0, 25.0), 0.9],
		["Bones", Vector3(13.2, 0, 28.0), 2.3],
		["Rubble", Vector3(6.0, 0, 19.6), 0.4],
		["Candles", Vector3(-1.3, 0, 24.0), 0.0],
		["Candles", Vector3(1.3, 0, 26.6), 1.0],
		# crypt: sarcophagi against the long walls, candles on the lids, the forgotten
		["Sarcophagus", Vector3(-27.0, 0, 20.6), 0.0, Vector2(2.3, 1.1), 1.0],
		["Sarcophagus", Vector3(-23.0, 0, 20.6), 0.0, Vector2(2.3, 1.1), 1.0],
		["Sarcophagus", Vector3(-19.0, 0, 20.6), 0.0, Vector2(2.3, 1.1), 1.0],
		["Sarcophagus", Vector3(-27.0, 0, 30.0), PI, Vector2(2.3, 1.1), 1.0],
		["Sarcophagus", Vector3(-23.0, 0, 30.0), PI, Vector2(2.3, 1.1), 1.0],
		["Sarcophagus", Vector3(-19.0, 0, 30.0), PI, Vector2(2.3, 1.1), 1.0],
		["Candles", Vector3(-23.0, 1.0, 20.6), 0.3],
		["Candles", Vector3(-19.0, 1.0, 30.0), 1.4],
		["Bones", Vector3(-25.0, 0, 25.3), 0.2],
		["SkeletonSit", Vector3(-29.4, 0, 30.6), PI / 2, Vector2(0.6, 0.9), 0.8],
		["Banner", Vector3(-23.0, 0.3, SOUTH + 0.2), 0.0],
		# chapel: pews facing the altar, braziers, banners, the altar stone
		["Pew", Vector3(19.5, 0, 21.6), -PI / 2, Vector2(0.5, 1.8), 0.9],
		["Pew", Vector3(22.5, 0, 21.6), -PI / 2, Vector2(0.5, 1.8), 0.9],
		["Pew", Vector3(25.5, 0, 21.6), -PI / 2, Vector2(0.5, 1.8), 0.9],
		["Pew", Vector3(19.5, 0, 29.0), -PI / 2, Vector2(0.5, 1.8), 0.9],
		["Pew", Vector3(22.5, 0, 29.0), -PI / 2, Vector2(0.5, 1.8), 0.9],
		["Pew", Vector3(25.5, 0, 29.0), -PI / 2, Vector2(0.5, 1.8), 0.9],
		["Sarcophagus", Vector3(28.6, 0, 29.6), PI / 2, Vector2(1.1, 2.3), 1.0],
		["Brazier", Vector3(28.5, 0, 20.6), 0.3, Vector2(0.8, 0.8), 1.1],
		["Candles", Vector3(28.6, 1.0, 29.6), 0.0],
		["Banner", Vector3(29.6, 0.3, 21.5), -PI / 2],
		["Banner", Vector3(29.6, 0.3, 28.5), -PI / 2],
		["Candles", Vector3(17.0, 0, 31.6), 0.6],
		# catacomb: the dead along the walls
		["Bones", Vector3(-2.3, 0, 34.5), 0.7],
		["Bones", Vector3(2.2, 0, 39.5), 2.6],
		["SkeletonSit", Vector3(-2.4, 0, 41.5), -PI / 2, Vector2(0.6, 0.9), 0.8],
		["Candles", Vector3(-2.4, 0, 37.0), 0.0],
		["Candles", Vector3(2.4, 0, 42.0), 1.2],
		["Rubble", Vector3(1.5, 0, 33.6), 1.9],
	]
	# two rows of graves either side of the monument
	for i in 4:
		var x := -11.0 + i * 1.7
		items.append(["Tombstone", Vector3(x, 0, 22.0), 0.1 * i, Vector2(0.75, 0.35), 0.9])
		items.append(["Tombstone", Vector3(x + 0.6, 0, 28.6), -0.1 * i, Vector2(0.75, 0.35), 0.9])
		items.append(["Tombstone", Vector3(-x, 0, 22.0), PI + 0.1 * i, Vector2(0.75, 0.35), 0.9])
		items.append(["Tombstone", Vector3(-x - 0.6, 0, 28.6), PI - 0.1 * i, Vector2(0.75, 0.35), 0.9])
	items.append(["TombstoneTall", Vector3(-6.0, 0, 25.3), PI / 2, Vector2(0.75, 0.75), 1.9])
	items.append(["TombstoneTall", Vector3(6.0, 0, 25.3), -PI / 2, Vector2(0.75, 0.75), 1.9])
	for it in items:
		_prop(it[0], it[1], it[2])
		if it.size() >= 5:
			var sz: Vector2 = it[3]
			var c: Vector3 = it[1]
			var blk := _box("Block_" + it[0], Vector3(c.x - sz.x / 2, 0, c.z - sz.y / 2), Vector3(c.x + sz.x / 2, it[4], c.z + sz.y / 2), "metal", "map_wall")
			blk.visible = false
	# spikes along the cloister fence beside the safe room
	for x in range(-15, -5, 2):
		_prop("SpikeRow", Vector3(x, FENCE_H, SOUTH), 0.0)
		_prop("SpikeRow", Vector3(-x, FENCE_H, SOUTH), 0.0)


func _wing_lights() -> void:
	# cloister: pale lamp light and a cold fill, the moon does the rest
	_omni("CloisterLampW", Vector3(-12.0, 3.3, 20.5), Color(0.62, 0.74, 1.0), 2.6, 13.0)
	_omni("CloisterLampE", Vector3(12.0, 3.3, 30.1), Color(0.62, 0.74, 1.0), 2.6, 13.0)
	_omni("CloisterFill", Vector3(0, 4.0, 25.3), Color(0.5, 0.55, 0.9), 1.4, 16.0)
	_omni("Monument", Vector3(0, 3.0, 24.5), VIOLET, 1.0, 5.0, true)
	# crypt: cold and violet
	_omni("CryptLight", Vector3(-23.0, 2.6, 25.3), COOL, 1.1, 10.0)
	_omni("CryptRift", Vector3(-23.0, 1.4, 25.3), VIOLET, 1.2, 6.0, true)
	# chapel: warm firelight from the braziers (fx) plus an amber overhead
	_prop("CeilingLamp", Vector3(23.0, H, 25.3), PI / 2)
	_omni("ChapelLight", Vector3(23.0, 2.7, 25.3), AMBER, 1.4, 10.0)
	# catacomb: dim, candle-lit
	_omni("CatacombLight", Vector3(0, 2.4, 38.0), Color(0.75, 0.62, 0.5), 0.9, 8.0, true)


func _wing_fx() -> void:
	var floor_rot := Vector3(-PI / 2, 0, 0)
	# cloister: ground mist, violet spores, brazier fire, candle light
	_fxm("mist", Vector3(0, 0.18, 25.3), floor_rot, {"size": Vector2(32, 14), "color": Color(0.42, 0.3, 0.62, 0.3), "speed": 0.9})
	_fxm("mist", Vector3(0, 0.55, 25.3), floor_rot, {"size": Vector2(32, 14), "color": Color(0.5, 0.36, 0.7, 0.14), "speed": 1.5})
	_fxm("motes", Vector3(0, 2.2, 25.3), Vector3.ZERO, {"extents": Vector3(15.0, 2.0, 6.5), "amount": 50, "color": Color(0.8, 0.45, 1.0)})
	for p in [Vector3(-3.4, 1.0, 20.4), Vector3(3.4, 1.0, 30.2), Vector3(28.5, 1.0, 20.6)]:
		_fxm("fire", p, Vector3.ZERO, {"energy": 2.0, "range": 7.0})
	for p in [Vector3(-1.3, 0.5, 24.0), Vector3(1.3, 0.5, 26.6), Vector3(-23.0, 1.5, 20.6), Vector3(-19.0, 1.5, 30.0),
			Vector3(28.6, 1.5, 29.6), Vector3(17.0, 0.5, 31.6), Vector3(-2.4, 0.5, 37.0), Vector3(2.4, 0.5, 42.0)]:
		_fxm("candle", p, Vector3.ZERO, {"energy": 0.8, "range": 3.2})
	# crypt: a rift over the central aisle, veins on the walls, drifting dust
	_fxm("rift", Vector3(-23.0, 2.5, 25.3), Vector3.ZERO, {"color": ARCANE})
	_fxm("sigil", Vector3(-29.83, 1.3, 21.0), Vector3(0, PI / 2, 0), {"tex": "veins", "size": Vector2(2.2, 2.6), "color": ARCANE, "energy": 1.2, "pulse": 0.35})
	_fxm("sigil", Vector3(-29.83, 1.3, 29.5), Vector3(0, PI / 2, 0), {"tex": "veins", "size": Vector2(2.2, 2.6), "color": ARCANE, "energy": 1.2, "pulse": 0.35})
	_fxm("motes", Vector3(-23.0, 1.5, 25.3), Vector3.ZERO, {"extents": Vector3(6.5, 1.2, 6.5), "amount": 20, "color": Color(0.7, 0.5, 1.0)})
	# chapel: warm dust and a light shaft under the lamp
	_fxm("motes", Vector3(23.0, 1.5, 25.3), Vector3.ZERO, {"extents": Vector3(6.5, 1.2, 6.5), "amount": 16, "color": Color(1.0, 0.75, 0.45)})
	_fxm("shaft", Vector3(23.0, H - 0.05, 25.3), Vector3.ZERO, {"color": AMBER, "energy": 0.14})
	# catacomb: thin mist along the floor
	_fxm("mist", Vector3(0, 0.2, 38.0), floor_rot, {"size": Vector2(6, 11), "color": Color(0.4, 0.32, 0.5, 0.25), "speed": 0.6})
