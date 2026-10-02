class_name ZombieView
extends Node3D
## Presentation of one zombie: interpolates sim state and plays procedural
## animation. Art integration: set zombies.<type>.model in data/visuals.json
## to a scene with an AnimationPlayer exposing "walk", "attack", "death"
## (and optionally "idle"); the placeholder rig is then skipped.

const CORPSE_SEC := 4.0

static var _mesh_cache := {}
static var _flash_mat: StandardMaterial3D
static var _shadow_mesh: QuadMesh

var zid: int
var ztype: String
var def: Dictionary
var vis: Dictionary
var prev_pos := Vector2.ZERO
var cur_pos := Vector2.ZERO
var prev_yaw: float = 0.0
var cur_yaw: float = 0.0
var dead: bool = false

var _rig: Node3D
var _body: MeshInstance3D
var _head: MeshInstance3D
var _arms: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _phase: float = 0.0
var _speed: float = 0.0
var _attack_t: float = -1.0
var _attack_len: float = 0.4
var _flash_t: float = 0.0
var _death_t: float = 0.0
var _busy_t: float = 0.0          ## attack/hit animation time left (model path)
var _meshes: Array[MeshInstance3D] = []

const STRIKE_SEC := 13.0 / 30.0   ## frame the attack lands in the authored animation
const LOOPING := ["idle", "walk", "run"]
static var _eye_mats := {}  ## zombie type -> shared eye material


func setup(zombie_id: int, type: String, zombie_def: Dictionary, pos: Vector2, yaw: float) -> void:
	zid = zombie_id
	ztype = type
	def = zombie_def
	vis = Visuals.zombie(type)
	prev_pos = pos
	cur_pos = pos
	prev_yaw = yaw
	cur_yaw = yaw
	_phase = randf() * TAU
	_model = Visuals.try_model(vis.get("model", ""))
	if _model:
		add_child(_model)
		_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _anim:
			for n in LOOPING:
				if _anim.has_animation(n):
					_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			_anim.playback_default_blend_time = 0.15
			_play("idle")
			_anim.seek(randf() * 1.5)  # desync crowds
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(mi)
			_tint_eyes(mi as MeshInstance3D)
	else:
		_build_placeholder()
	var shadow := MeshInstance3D.new()
	shadow.mesh = _shadow()
	shadow.rotation.x = -PI / 2
	shadow.position.y = 0.02
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	_apply_transform(1.0)


## Eye glow comes from visuals.json ("eyes"), so the look can change without re-exporting the model.
func _tint_eyes(mi: MeshInstance3D) -> void:
	if mi.mesh == null or not vis.has("eyes"):
		return
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if src and src.resource_name.to_lower().begins_with("eyes"):
			var m := _eye_mats.get(ztype) as BaseMaterial3D
			if m == null:
				m = src.duplicate() as BaseMaterial3D
				m.albedo_color = Color(vis.eyes)
				m.emission_enabled = true
				m.emission = Color(vis.eyes)
				m.emission_energy_multiplier = 3.0
				_eye_mats[ztype] = m
			mi.set_surface_override_material(i, m)


func set_sim_state(pos: Vector2, yaw: float, moving: bool) -> void:
	prev_pos = cur_pos
	prev_yaw = cur_yaw
	cur_pos = pos
	cur_yaw = yaw
	_speed = (cur_pos - prev_pos).length() * 20.0 if moving else 0.0


func update_view(alpha: float, delta: float, far := false) -> void:
	if dead:
		_update_death(delta)
		return
	_apply_transform(alpha)
	if _model:
		if far:
			# far on a low phone: hold the pose, skip the animation player
			if _anim and _anim.is_playing() and _anim.current_animation in LOOPING:
				_anim.pause()
			return
		if _anim and not _anim.is_playing() and _busy_t <= 0.0:
			_anim.play()
		_update_model_anim(delta)
		return
	_phase += delta * (2.5 + _speed * 2.2)
	var sway: float = vis.get("sway", 0.1)
	var moving := _speed > 0.2
	_rig.rotation.z = sin(_phase) * sway * (1.0 if moving else 0.3)
	_rig.position.y = absf(sin(_phase)) * (0.05 if moving else 0.01)
	var arm_x := -0.15 + sin(_phase * 2.0) * 0.06
	if _attack_t >= 0.0:
		_attack_t += delta
		var k := _attack_t / _attack_len
		arm_x = lerpf(-0.15, 0.9, clampf(k, 0, 1)) if k < 1.0 else lerpf(0.9, -0.5, clampf((k - 1.0) * 5.0, 0, 1))
		if k > 1.4:
			_attack_t = -1.0
	_arms.rotation.x = arm_x
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_overlay(null)


func on_attack(windup: float) -> void:
	_attack_len = windup
	_attack_t = 0.0
	if _anim:
		var speed := STRIKE_SEC / maxf(windup, 0.05)  # land the swing exactly when the sim deals damage
		_anim.speed_scale = 1.0
		_anim.play("attack", 0.1, speed)
		_busy_t = _anim.get_animation("attack").length / speed if _anim.has_animation("attack") else windup


func on_hit() -> void:
	_flash_t = 0.08
	_set_overlay(_flash())
	if _anim and _busy_t <= 0.0 and _anim.has_animation("hit"):
		_anim.speed_scale = 1.0
		_anim.play("hit", 0.05, 1.6)
		_busy_t = _anim.get_animation("hit").length / 1.6


func on_death(pos: Vector2, yaw: float) -> void:
	dead = true
	cur_pos = pos
	prev_pos = pos
	cur_yaw = yaw
	_apply_transform(1.0)
	_set_overlay(null)
	_busy_t = 999.0
	if _anim:
		_anim.speed_scale = 1.0
		_anim.play("death", 0.08, 1.0)


func _update_model_anim(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_overlay(null)
	if _anim == null:
		return
	if _busy_t > 0.0:
		_busy_t -= delta
		return
	if _speed > 0.2:
		var loco: String = vis.get("locomotion", "walk")
		var nominal: float = vis.get("locoSpeed", 1.2)
		_play(loco, clampf(_speed / nominal, 0.6, 1.8))
	else:
		_play("idle")


func _update_death(delta: float) -> void:
	_death_t += delta
	if _rig:
		var k := clampf(_death_t / 0.45, 0.0, 1.0)
		_rig.rotation.x = lerpf(0.0, PI / 2 * 0.95, k * k)
		_rig.position.y = lerpf(0.0, 0.15, k)
		_rig.rotation.z = 0.0
	if _death_t > CORPSE_SEC:
		position.y -= delta * 0.5
	if _death_t > CORPSE_SEC + 1.5:
		queue_free()


func _apply_transform(alpha: float) -> void:
	var p := prev_pos.lerp(cur_pos, alpha)
	position = Vector3(p.x, position.y if dead else 0.0, p.y)
	rotation.y = lerp_angle(prev_yaw, cur_yaw, alpha)


func _play(anim: String, speed := 1.0) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	_anim.speed_scale = speed
	if _anim.current_animation != anim:
		_anim.play(anim)


func _set_overlay(m: Material) -> void:
	for mi in _meshes:
		mi.material_overlay = m
	for mi in [_body, _head]:
		if mi:
			mi.material_overlay = m
	if _arms and _arms.get_child_count() > 0:
		(_arms.get_child(0) as MeshInstance3D).material_overlay = m


func _build_placeholder() -> void:
	var meshes := _meshes_for(ztype)
	var s: float = vis.get("scale", 1.0)
	_rig = Node3D.new()
	_rig.rotation.x = 0.0
	add_child(_rig)
	var lean := Node3D.new()
	lean.rotation.x = -float(vis.get("lean", 0.0))
	lean.scale = Vector3(s, 1.0, s)
	_rig.add_child(lean)
	_body = MeshInstance3D.new()
	_body.mesh = meshes.body
	lean.add_child(_body)
	_head = MeshInstance3D.new()
	_head.mesh = meshes.head
	_head.position.y = float(def.headCenterHeight)
	lean.add_child(_head)
	_arms = Node3D.new()
	_arms.position = Vector3(0, float(def.headCenterHeight) - 0.27, -0.02)
	lean.add_child(_arms)
	var arms_mi := MeshInstance3D.new()
	arms_mi.mesh = meshes.arms
	_arms.add_child(arms_mi)


static func _meshes_for(type: String) -> Dictionary:
	if _mesh_cache.has(type):
		return _mesh_cache[type]
	var v := Visuals.zombie(type)
	var cloth := MeshKit.mat(Color(v.cloth))
	var skin := MeshKit.mat(Color(v.skin))
	var eyes := MeshKit.mat(Color(v.eyes), 1.0, Color(v.eyes))
	var neck_y := 1.4
	var body := MeshKit.merge([
		{"mesh": MeshKit.box(Vector3(0.14, 0.82, 0.16)), "xform": MeshKit.xf(Vector3(-0.1, 0.41, 0)), "mat": 0},
		{"mesh": MeshKit.box(Vector3(0.14, 0.82, 0.16)), "xform": MeshKit.xf(Vector3(0.1, 0.41, 0.03), Vector3(0.12, 0, 0)), "mat": 0},
		{"mesh": MeshKit.box(Vector3(0.44, 0.6, 0.25)), "xform": MeshKit.xf(Vector3(0, 1.1, 0), Vector3(0.08, 0, 0.05)), "mat": 0},
		{"mesh": MeshKit.cylinder(0.06, 0.16), "xform": MeshKit.xf(Vector3(0, neck_y + 0.02, 0)), "mat": 1},
	], [cloth, skin])
	var head := MeshKit.merge([
		{"mesh": MeshKit.sphere(0.16), "xform": MeshKit.xf(Vector3.ZERO), "mat": 0},
		{"mesh": MeshKit.box(Vector3(0.05, 0.025, 0.02)), "xform": MeshKit.xf(Vector3(-0.06, 0.02, -0.145)), "mat": 1},
		{"mesh": MeshKit.box(Vector3(0.05, 0.025, 0.02)), "xform": MeshKit.xf(Vector3(0.06, 0.02, -0.145)), "mat": 1},
	], [skin, eyes])
	var arms := MeshKit.merge([
		{"mesh": MeshKit.box(Vector3(0.1, 0.1, 0.5)), "xform": MeshKit.xf(Vector3(-0.27, 0, -0.22)), "mat": 0},
		{"mesh": MeshKit.box(Vector3(0.1, 0.1, 0.5)), "xform": MeshKit.xf(Vector3(0.27, 0, -0.22), Vector3(0.1, 0, 0)), "mat": 0},
		{"mesh": MeshKit.box(Vector3(0.09, 0.08, 0.12)), "xform": MeshKit.xf(Vector3(-0.27, 0, -0.52)), "mat": 1},
		{"mesh": MeshKit.box(Vector3(0.09, 0.08, 0.12)), "xform": MeshKit.xf(Vector3(0.27, -0.04, -0.5)), "mat": 1},
	], [cloth, skin])
	_mesh_cache[type] = {"body": body, "head": head, "arms": arms}
	return _mesh_cache[type]


static func _flash() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1, 0.85, 0.8, 0.55)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return _flash_mat


static func _shadow() -> QuadMesh:
	if _shadow_mesh == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = tex
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_shadow_mesh = QuadMesh.new()
		_shadow_mesh.size = Vector2(1.0, 1.0)
		_shadow_mesh.material = m
	return _shadow_mesh
