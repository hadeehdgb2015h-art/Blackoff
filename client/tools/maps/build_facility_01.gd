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
	_walls()
	_props()
	_markers()
	_lights()
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
	_hwall("SafeS", 18, -5, 5, [])
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
		["LampPost", Vector3(-15, 0, -7.2), 0.0, Vector2(0.4, 0.4), 4.0],
		["LampPost", Vector3(15, 0, -7.2), 0.0, Vector2(0.4, 0.4), 4.0],
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
		["Rubble", Vector3(-3.0, 0, -21.0), 1.3],
		["Rubble", Vector3(10.0, 0, -9.0), 0.2],
	]
	for it in items:
		_prop(it[0], it[1], it[2])
		if it.size() >= 5:
			var sz: Vector2 = it[3]
			var c: Vector3 = it[1]
			var blk := _box("Block_" + it[0], Vector3(c.x - sz.x / 2, 0, c.z - sz.y / 2), Vector3(c.x + sz.x / 2, it[4], c.z + sz.y / 2), "metal", "map_wall")
			blk.visible = false
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
	var spawns := [Vector2(-1.5, 15.5), Vector2(1.5, 15.5), Vector2(-1.5, 17.0), Vector2(1.5, 17.0)]
	for i in spawns.size():
		var m := _marker("PlayerSpawn%d" % (i + 1), spawns[i], "map_player_spawn")
		m.rotation.y = 0.0
	var entries := [
		["yard_nw", Vector2(-10, -25.8), Vector2(-10, -22.5)],
		["yard_ne", Vector2(10, -25.8), Vector2(10, -22.5)],
		["lab_window", Vector2(-19.8, -2), Vector2(-16.5, -2)],
		["storage_window", Vector2(19.8, -2), Vector2(16.5, -2)],
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
	_omni("Breach", Vector3(-7.5, 1.6, -20.0), VIOLET, 3.2, 13.0)
	_omni("PostW", Vector3(-15, 3.8, -7.92), AMBER, 3.0, 15.0)
	_omni("PostE", Vector3(15, 3.8, -7.92), AMBER, 3.0, 15.0)
	_omni("YardFill", Vector3(0, 4.0, -15.0), Color(0.55, 0.62, 0.95), 1.6, 16.0)
	_omni("GenLight", Vector3(16.9, 0.9, -12.5), Color(1.0, 0.25, 0.2), 0.7, 3.0, true)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.6, 0.62, 0.95)
	moon.light_energy = 1.15
	moon.rotation = Vector3(deg_to_rad(-48), deg_to_rad(35), 0)
	moon.shadow_enabled = false
	moon.light_cull_mask = 2  # outdoor layer only (MapBatcher puts yard meshes on layer 2)
	_add(lights, moon)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.04, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.62, 0.7)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.16, 0.3)
	env.fog_density = 0.012
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(map_root, we)


# ---------------------------------------------------------------- helpers

func _hwall(name: String, z: float, x0: float, x1: float, gaps: Array, h := H, mat := "wall") -> void:
	for seg in _split(x0, x1, gaps):
		_box("%s_%d" % [name, geo.get_child_count()], Vector3(seg.x - T / 2, 0, z - T / 2), Vector3(seg.y + T / 2, h, z + T / 2), mat, "map_wall")
		_dress(seg.x - T / 2, seg.y + T / 2, z, false, h, mat)
	if h == H and mat == "wall":
		for g in gaps:
			_prop("DoorFrame25" if g[1] > 2.2 else "DoorFrame2", Vector3(g[0], 0, z), 0.0)


func _vwall(name: String, x: float, z0: float, z1: float, gaps: Array, h := H, mat := "wall") -> void:
	for seg in _split(z0, z1, gaps):
		_box("%s_%d" % [name, geo.get_child_count()], Vector3(x - T / 2, 0, seg.x - T / 2), Vector3(x + T / 2, h, seg.y + T / 2), mat, "map_wall")
		_dress(seg.x - T / 2, seg.y + T / 2, x, true, h, mat)
	if h == H and mat == "wall":
		for g in gaps:
			_prop("DoorFrame25" if g[1] > 2.2 else "DoorFrame2", Vector3(x, 0, g[0]), PI / 2)


## Visual wall dressing (no collision): baseboard, cornice and pillars on both
## faces of interior walls; posts on fences. `vertical` = wall runs along Z.
func _dress(a: float, b: float, at: float, vertical: bool, h: float, mat: String) -> void:
	var boxes := []
	if mat == "wall" and h == H:
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


func _floor(name: String, r: Rect2, mat: String) -> void:
	_box("Floor_" + name, Vector3(r.position.x, -0.2, r.position.y), Vector3(r.end.x, 0, r.end.y), mat, "map_floor")


func _box(name: String, mn: Vector3, mx: Vector3, mat: String, group: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var mesh := BoxMesh.new()
	mesh.size = mx - mn
	mi.mesh = mesh
	mi.material_override = mats[mat]
	mi.position = (mn + mx) / 2.0
	mi.add_to_group(group, true)
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
