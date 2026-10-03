class_name PerkMachineView
extends Node3D
## A perk vending machine on the map: dark cabinet, a glowing front panel in
## the perk's colour, the perk name and price above, a soft light, and a
## bottle silhouette behind the glass. Procedural (MeshKit), no art asset.
## Front faces local -Z (the interaction side); `yaw` from the map turns it.

var perk_id: String
var _panel_mat: StandardMaterial3D
var _light := OmniLight3D.new()
var _t: float = 0.0


func setup(id: String, def: Dictionary, pos: Vector2, yaw: float) -> void:
	perk_id = id
	position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = yaw
	var col := Color(str(def.get("color", "#ffffff")))
	var cabinet := MeshKit.mat(Color(0.12, 0.12, 0.13), 0.55)
	var trim := MeshKit.mat(col.darkened(0.35), 0.4)
	_panel_mat = MeshKit.mat(col.darkened(0.55), 0.25, col)
	_panel_mat.emission_energy_multiplier = 2.4
	var glass := MeshKit.mat(Color(0.05, 0.07, 0.09, 0.85), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var bottle := MeshKit.mat(col, 0.3, col)
	bottle.emission_energy_multiplier = 0.8
	var body := MeshInstance3D.new()
	body.mesh = MeshKit.merge([
		{"mesh": MeshKit.box(Vector3(0.9, 1.95, 0.8)), "xform": MeshKit.xf(Vector3(0, 0.975, 0)), "mat": 0},
		{"mesh": MeshKit.box(Vector3(0.96, 0.1, 0.86)), "xform": MeshKit.xf(Vector3(0, 1.95, 0)), "mat": 1},  # top band
		{"mesh": MeshKit.box(Vector3(0.96, 0.12, 0.86)), "xform": MeshKit.xf(Vector3(0, 0.06, 0)), "mat": 1},  # base
		{"mesh": MeshKit.box(Vector3(0.78, 0.34, 0.03)), "xform": MeshKit.xf(Vector3(0, 1.72, -0.41)), "mat": 2},  # lit header
		{"mesh": MeshKit.box(Vector3(0.62, 0.95, 0.03)), "xform": MeshKit.xf(Vector3(-0.08, 1.05, -0.41)), "mat": 3},  # window
		{"mesh": MeshKit.box(Vector3(0.1, 0.9, 0.03)), "xform": MeshKit.xf(Vector3(0.36, 1.0, -0.41)), "mat": 2},  # side light strip
		{"mesh": MeshKit.box(Vector3(0.3, 0.2, 0.08)), "xform": MeshKit.xf(Vector3(0.0, 0.42, -0.42)), "mat": 1},  # dispenser
		{"mesh": MeshKit.cylinder(0.07, 0.3), "xform": MeshKit.xf(Vector3(-0.08, 1.0, -0.3)), "mat": 4},  # bottle
		{"mesh": MeshKit.cylinder(0.03, 0.1), "xform": MeshKit.xf(Vector3(-0.08, 1.2, -0.3)), "mat": 4},  # bottle neck
	], [cabinet, trim, _panel_mat, glass, bottle])
	add_child(body)
	_light.light_color = col
	_light.omni_range = 3.0
	_light.light_energy = 0.9
	_light.position = Vector3(0, 1.3, -0.9)
	_light.shadow_enabled = false
	add_child(_light)
	var name_label := Label3D.new()
	name_label.text = I18n.name_of(str(def.get("displayName", id))).to_upper()
	name_label.font_size = 44
	name_label.pixel_size = 0.004
	name_label.outline_size = 10
	name_label.modulate = col.lightened(0.35)
	name_label.position = Vector3(0, 2.3, -0.45)
	name_label.rotation.y = PI
	add_child(name_label)
	var price := Label3D.new()
	price.text = "$%d" % int(def.get("price", 0))
	price.font_size = 34
	price.pixel_size = 0.004
	price.outline_size = 8
	price.modulate = Color(0.95, 0.85, 0.5)
	price.position = Vector3(0, 2.12, -0.45)
	price.rotation.y = PI
	add_child(price)


func _process(delta: float) -> void:
	_t += delta
	_panel_mat.emission_energy_multiplier = 2.3 + sin(_t * 3.0) * 0.3
	_light.light_energy = 0.85 + sin(_t * 3.0) * 0.15
