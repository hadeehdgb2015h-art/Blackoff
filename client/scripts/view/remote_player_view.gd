class_name RemotePlayerView
extends Node3D
## Another player in online play: interpolated body, held weapon, name tag.
## Uses visuals.json `players.soldier` (soldier.glb: idle_/run_<hold> for the hold
## classes long, smg and pistol, plus downed) and falls back to a procedural
## figure if the model is missing. The held weapon is the first-person model with
## its Root reset (origin = trigger grip), placed per hold class; the soldier's
## arms are solved onto exactly that placement at build time
## (art/blender/build_soldier.py, HOLDS).

var pid: int = -1
var _prev := Vector2.ZERO
var _cur := Vector2.ZERO
var _yaw_prev: float = 0.0
var _yaw: float = 0.0
var _moving: bool = false
var _downed: bool = false
var _weapon_id: String = ""
var _body: Node3D
var _legs: Array[Node3D] = []
var _gun_holder: Node3D
var _name: Label3D
var _phase: float = 0.0
var _kick: float = 0.0
var _anim: AnimationPlayer
var _run_speed: float = 3.8
var _speed: float = 0.0
var _vis: Dictionary = {}
var _hold: String = "long"


func setup(p: SimPlayer) -> void:
	pid = p.id
	_prev = p.pos
	_cur = p.pos
	_yaw = p.yaw
	_yaw_prev = p.yaw
	_body = Node3D.new()
	add_child(_body)
	var vis: Dictionary = Visuals.data().get("players", {}).get("soldier", {})
	_vis = vis
	var model := Visuals.try_model(str(vis.get("model", "")))
	if model:
		_body.add_child(model)
		_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _anim:
			for n in _anim.get_animation_list():
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			_anim.playback_default_blend_time = 0.2
		_run_speed = float(vis.get("runSpeed", 3.8))
	else:
		_build_placeholder()
	_gun_holder = Node3D.new()
	_gun_holder.position = Vector3(0.17, 1.33, -0.31)
	_body.add_child(_gun_holder)
	_name = Label3D.new()
	_name.position = Vector3(0, 2.15, 0)
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.font_size = 44
	_name.pixel_size = 0.004
	_name.outline_size = 10
	_name.modulate = Color(0.75, 0.95, 1.0)
	_name.no_depth_test = true
	add_child(_name)
	set_state(p)
	_apply(1.0)


func set_state(p: SimPlayer) -> void:
	_prev = _cur
	_cur = p.pos
	_yaw_prev = _yaw
	_yaw = p.yaw
	_moving = p.moving
	_downed = p.state != SimPlayer.State.ALIVE
	_name.text = p.name
	var wid := p.weapon().id if p.weapon() else ""
	if wid != _weapon_id:
		_weapon_id = wid
		for c in _gun_holder.get_children():
			c.queue_free()
		if wid != "":
			_gun_holder.add_child(Visuals.weapon_world_node(wid))
		_hold = str(_vis.get("weaponHold", {}).get(wid, "long"))
		var h: Dictionary = _vis.get("holds", {}).get(_hold, {})
		if not h.is_empty():
			_gun_holder.position = Vector3(h.pos[0], h.pos[1], h.pos[2])
			_gun_holder.scale = Vector3.ONE * float(h.scale)


func on_fire() -> void:
	_kick = 1.0


func update_view(alpha: float, delta: float) -> void:
	var before := position
	_apply(alpha)
	if delta > 0.0:
		var v := Vector2(position.x - before.x, position.z - before.z).length() / delta
		_speed = lerpf(_speed, v, minf(1.0, delta * 8.0))
	_kick = maxf(0.0, _kick - delta * 8.0)
	_gun_holder.visible = not _downed
	if _anim:
		var running := _moving and _speed > 0.4
		var want := "downed" if _downed else ("%s_%s" % ["run" if running else "idle", _hold])
		if not _anim.has_animation(want):
			want = "run_long" if running else "idle_long"
		if _anim.current_animation != want:
			_anim.play(want)
		_anim.speed_scale = clampf(_speed / _run_speed, 0.5, 1.6) if running else 1.0
		_gun_holder.rotation.x = 0.06 * _kick
		return
	if _moving:
		_phase += delta * 9.0
	for i in _legs.size():
		_legs[i].rotation.x = sin(_phase + PI * i) * (0.55 if _moving else 0.0)
	_gun_holder.rotation.x = 0.06 * _kick
	# Downed placeholder lies on its back; the name tag stays readable.
	var target_tilt := -PI / 2 if _downed else 0.0
	_body.rotation.x = lerpf(_body.rotation.x, target_tilt, minf(1.0, delta * 6.0))
	_body.position.y = lerpf(_body.position.y, 0.35 if _downed else 0.0, minf(1.0, delta * 6.0))


func _apply(alpha: float) -> void:
	var p := _prev.lerp(_cur, alpha)
	position = Vector3(p.x, 0, p.y)
	rotation.y = lerp_angle(_yaw_prev, _yaw, alpha)


func _build_placeholder() -> void:
	var cloth := MeshKit.mat(Color(0.2, 0.22, 0.2), 0.9)
	var gear := MeshKit.mat(Color(0.12, 0.12, 0.13), 0.7)
	var skin := MeshKit.mat(Color(0.62, 0.48, 0.4), 0.8)
	var mark := MeshKit.mat(Color(0.2, 0.9, 1.0), 0.5, Color(0.2, 0.9, 1.0))
	var torso := _part(CapsuleMesh.new(), cloth, Vector3(0, 1.15, 0))
	(torso.mesh as CapsuleMesh).radius = 0.22
	(torso.mesh as CapsuleMesh).height = 0.75
	var vest := _part(BoxMesh.new(), gear, Vector3(0, 1.18, -0.02))
	(vest.mesh as BoxMesh).size = Vector3(0.42, 0.42, 0.3)
	var head := _part(SphereMesh.new(), skin, Vector3(0, 1.62, 0))
	(head.mesh as SphereMesh).radius = 0.12
	(head.mesh as SphereMesh).height = 0.26
	var helmet := _part(SphereMesh.new(), gear, Vector3(0, 1.67, 0.01))
	(helmet.mesh as SphereMesh).radius = 0.145
	(helmet.mesh as SphereMesh).height = 0.2
	var strip := _part(BoxMesh.new(), mark, Vector3(0, 1.72, 0.13))
	(strip.mesh as BoxMesh).size = Vector3(0.1, 0.025, 0.02)  # ally marker on the helmet back
	for sx in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * sx, 0.78, 0)
		_body.add_child(hip)
		var leg := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.09
		cm.height = 0.8
		leg.mesh = cm
		leg.material_override = cloth
		leg.position = Vector3(0, -0.38, 0)
		hip.add_child(leg)
		_legs.append(hip)


func _part(mesh: PrimitiveMesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_body.add_child(mi)
	return mi
