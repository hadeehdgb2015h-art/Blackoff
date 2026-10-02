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
	# name, min (x,y,z), max (x,y,z), material — all block movement; height decides bullet blocking.
	var props := [
		["CrateStack", Vector3(-5.6, 0, -14.6), Vector3(-4.4, 1.0, -13.4), "crate"],
		["CrateRow", Vector3(4.8, 0, -17.6), Vector3(7.2, 1.1, -16.4), "crate"],
		["Container", Vector3(-2.5, 0, -12.1), Vector3(2.5, 2.4, -9.9), "container"],
		["Barrier", Vector3(-14.3, 0, -18.5), Vector3(-13.7, 1.0, -15.5), "hazard"],
		["Barrier2", Vector3(13.7, 0, -20.5), Vector3(14.3, 1.0, -17.5), "hazard"],
		["LabBench", Vector3(-15, 0, -4.0), Vector3(-11, 0.95, -3.0), "metal"],
		["Shelving", Vector3(11, 0, -4.0), Vector3(15, 2.2, -3.2), "metal"],
		["AmmoCrate", Vector3(-0.6, 0, 10.15), Vector3(0.6, 0.8, 10.75), "ammo"],
	]
	for p in props:
		_box(p[0], p[1], p[2], p[3], "map_wall")


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
	var safe := _marker("SafeArea", Vector2(0, 14), "map_safe_area")
	safe.set_meta("min", Vector2(-5, 10))
	safe.set_meta("max", Vector2(5, 18))


func _lights() -> void:
	_omni("SafeLight", Vector3(0, 2.7, 14), Color(0.75, 0.85, 1.0), 1.1, 9.0)
	_omni("CorrW_Red", Vector3(-13, 2.6, 7), Color(1, 0.15, 0.1), 1.6, 7.0)
	_omni("CorrE_Red", Vector3(13, 2.6, 7), Color(1, 0.15, 0.1), 1.6, 7.0)
	_omni("CorrW_Amber", Vector3(-9, 2.6, 14), Color(1, 0.55, 0.15), 1.2, 6.0)
	_omni("CorrE_Amber", Vector3(9, 2.6, 14), Color(1, 0.55, 0.15), 1.2, 6.0)
	_omni("LabLight", Vector3(-13, 2.7, -2), Color(1, 0.6, 0.25), 1.3, 10.0)
	_omni("StorageLight", Vector3(13, 2.7, -2), Color(1, 0.6, 0.25), 1.3, 10.0)
	_omni("YardLamp", Vector3(0, 5.0, -17), Color(1, 0.7, 0.35), 2.0, 16.0)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.35
	moon.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	moon.shadow_enabled = false
	_add(lights, moon)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.28)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.1, 0.13)
	env.fog_density = 0.035
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(map_root, we)


# ---------------------------------------------------------------- helpers

func _hwall(name: String, z: float, x0: float, x1: float, gaps: Array, h := H, mat := "wall") -> void:
	for seg in _split(x0, x1, gaps):
		_box("%s_%d" % [name, geo.get_child_count()], Vector3(seg.x - T / 2, 0, z - T / 2), Vector3(seg.y + T / 2, h, z + T / 2), mat, "map_wall")


func _vwall(name: String, x: float, z0: float, z1: float, gaps: Array, h := H, mat := "wall") -> void:
	for seg in _split(z0, z1, gaps):
		_box("%s_%d" % [name, geo.get_child_count()], Vector3(x - T / 2, 0, seg.x - T / 2), Vector3(x + T / 2, h, seg.y + T / 2), mat, "map_wall")


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


func _omni(name: String, pos: Vector3, color: Color, energy: float, rng: float) -> void:
	var o := OmniLight3D.new()
	o.name = name
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.shadow_enabled = false
	o.add_to_group("map_light", true)
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
	var defs := {
		"wall": [Color(0.36, 0.38, 0.37), grime, 0.5],
		"floor_concrete": [Color(0.3, 0.3, 0.31), grime, 0.35],
		"ceiling": [Color(0.18, 0.19, 0.2), grime, 0.5],
		"ground_yard": [Color(0.2, 0.21, 0.19), grime, 0.25],
		"fence": [Color(0.28, 0.27, 0.25), grime, 0.6],
		"crate": [Color(0.42, 0.33, 0.2), grime, 0.8],
		"container": [Color(0.22, 0.32, 0.3), grime, 0.4],
		"metal": [Color(0.42, 0.44, 0.46), grime, 0.7],
		"hazard": [Color(1, 1, 1), hazard, 0.5],
		"ammo": [Color(0.25, 0.32, 0.18), grime, 1.0],
		"panel_buy": [Color(0.9, 0.7, 0.2), null, 1.0],
	}
	for k in defs:
		var m := StandardMaterial3D.new()
		m.resource_name = k
		m.albedo_color = defs[k][0]
		if defs[k][1] != null:
			m.albedo_texture = defs[k][1]
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * defs[k][2]
		m.roughness = 0.9
		if k == "panel_buy":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.65, 0.15)
			m.emission_energy_multiplier = 1.4
		mats[k] = m
