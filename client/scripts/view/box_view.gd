class_name BoxView
extends Node3D
## Supply cache presentation: lid opens, a glow comes on and weapon models
## shuffle (cosmetic only) until the sim reveals the result in `box_offer`.
## Art integration: res://assets/models/supply_box.glb with a child node
## named "Lid" (hinged at its origin) and optionally "GlowAnchor".

const MODEL := "res://assets/models/supply_box.glb"
const LID_OPEN := 1.9  ## radians around local X (hinge at the back edge)

var box_id: String
var _model: Node3D
var _lid: Node3D
var _glow := OmniLight3D.new()
var _weapon := Node3D.new()          ## holder; one child per pool weapon, one visible
var _weapon_nodes := {}
var _lid_target: float = 0.0
var _rolling: bool = false
var _offer: bool = false
var _shuffle_t: float = 0.0
var _shuffle_step: float = 0.08
var _roll_left: float = 0.0
var _pool: Array = []
var _t: float = 0.0


func setup(id: String, pos: Vector2, facing_yaw: float, weapon_pool: Array) -> void:
	box_id = id
	_pool = weapon_pool
	position = Vector3(pos.x, 0, pos.y)
	rotation.y = facing_yaw
	_model = Visuals.try_model(MODEL)
	if _model == null:
		_model = _placeholder()
	add_child(_model)
	_lid = _model.find_child("Lid", true, false) as Node3D
	var anchor := _model.find_child("GlowAnchor", true, false) as Node3D
	_glow.position = anchor.position if anchor else Vector3(0, 0.9, 0)
	_glow.light_color = Color(1.0, 0.55, 0.2)
	_glow.omni_range = 4.0
	_glow.light_energy = 0.0
	_glow.visible = false
	add_child(_glow)
	_weapon.position = Vector3(0, 0.75, 0)
	_weapon.rotation.y = PI / 2
	_weapon.visible = false
	add_child(_weapon)
	for wid in _pool:
		var n := Visuals.weapon_world_node(wid)
		n.visible = false
		_weapon.add_child(n)
		_weapon_nodes[wid] = n


func on_open(roll_sec: float) -> void:
	_rolling = true
	_offer = false
	_roll_left = roll_sec
	_shuffle_step = 0.07
	_lid_target = LID_OPEN
	_glow.visible = true
	_weapon.visible = true


func on_offer(weapon_id: String) -> void:
	_rolling = false
	_offer = true
	_show_weapon(weapon_id)
	_weapon.visible = true


func on_close() -> void:
	_rolling = false
	_offer = false
	_weapon.visible = false
	_lid_target = 0.0
	_glow.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _lid:
		_lid.rotation.x = lerpf(_lid.rotation.x, _lid_target, minf(1.0, delta * 6.0))
	if _glow.visible:
		_glow.light_energy = 1.6 + sin(_t * 9.0) * 0.4
	if _rolling:
		_roll_left -= delta
		_shuffle_t -= delta
		_weapon.position.y = lerpf(_weapon.position.y, 1.05, delta * 2.0)
		if _shuffle_t <= 0.0 and not _pool.is_empty():
			_show_weapon(_pool[randi() % _pool.size()])
			_shuffle_step = lerpf(_shuffle_step, 0.3, 0.12)  # slows down as the roll ends
			_shuffle_t = _shuffle_step
	elif _offer:
		_weapon.rotation.y += delta * 1.2
		_weapon.position.y = 1.05 + sin(_t * 2.0) * 0.04
	else:
		_weapon.position.y = 0.75


func _show_weapon(id: String) -> void:
	if not _weapon_nodes.has(id):
		var n := Visuals.weapon_world_node(id)
		_weapon.add_child(n)
		_weapon_nodes[id] = n
	for k in _weapon_nodes:
		_weapon_nodes[k].visible = k == id


func _placeholder() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = MeshKit.merge([
		{"mesh": MeshKit.box(Vector3(1.4, 0.62, 0.7)), "xform": MeshKit.xf(Vector3(0, 0.31, 0)), "mat": 0},
		{"mesh": MeshKit.box(Vector3(1.44, 0.06, 0.74)), "xform": MeshKit.xf(Vector3(0, 0.08, 0)), "mat": 1},
	], [MeshKit.mat(Color(0.26, 0.3, 0.2)), MeshKit.mat(Color(0.15, 0.15, 0.15), 0.5)])
	root.add_child(body)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.62, 0.35)
	var lid_mesh := MeshInstance3D.new()
	lid_mesh.mesh = MeshKit.merge([
		{"mesh": MeshKit.box(Vector3(1.42, 0.12, 0.72)), "xform": MeshKit.xf(Vector3(0, 0.06, -0.36)), "mat": 0},
	], [MeshKit.mat(Color(0.3, 0.34, 0.23))])
	lid.add_child(lid_mesh)
	root.add_child(lid)
	return root
