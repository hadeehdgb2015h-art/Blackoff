class_name FpRig
extends Node3D
## First-person camera and weapon viewmodel for the local player.
## Art integration: weapons.<id>.model in data/visuals.json. Model scenes are
## authored in CAMERA space (origin = eye, -Z forward) with nodes Root, Weapon,
## Mag, Slide, ArmL, ArmR, Muzzle and animations idle/fire/reload/draw
## (see art/blender/build_weapons.py). They are scaled by VM_SCALE about the
## camera: the image is unchanged but the gun no longer pokes through walls.

const BOB_FREQ := 9.0
const BOB_AMP := 0.012
const VM_SCALE := 0.5

var camera := Camera3D.new()
var muzzle_light_enabled: bool = false

var _vm_root := Node3D.new()     ## animated (recoil/reload/switch)
var _vm_holder := Node3D.new()   ## per-weapon offset
var _weapon_node: Node3D
var _muzzle := Node3D.new()
var _flash := MeshInstance3D.new()
var _light := OmniLight3D.new()
var _weapon_id := ""
var _vis: Dictionary = {}
var _kick: float = 0.0
var _bob_t: float = 0.0
var _flash_t: float = 0.0
var _reload_t: float = -1.0
var _reload_len: float = 1.0
var _switch_t: float = -1.0
var _pending_weapon := ""
var _shake: float = 0.0
var _fov_punch: float = 0.0  ## degrees added to the field of view, springing back (kills)
var _down: float = 0.0
var _anim: AnimationPlayer
var _claws: Node3D            ## infection: the infected player's hands instead of a weapon
var _claws_on: bool = false
var _claw_t: float = -1.0

static var _weapon_mesh_cache := {}


func _ready() -> void:
	_light.add_to_group("rig_light")
	camera.fov = 75.0
	camera.near = 0.03
	camera.far = 90.0
	add_child(camera)
	camera.add_child(_vm_root)
	_vm_root.add_child(_vm_holder)
	_flash.mesh = _flash_mesh()
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash)
	_light.light_color = Color(1.0, 0.75, 0.4)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.visible = false
	_muzzle.add_child(_light)


func set_weapon(id: String) -> void:
	if id == _weapon_id:
		return
	_weapon_id = id
	_vis = Visuals.weapon(id)
	if _weapon_node:
		_weapon_node.queue_free()
	_weapon_node = Visuals.try_model(_vis.get("model", ""))
	_anim = null
	if _weapon_node:
		_vm_holder.position = Vector3.ZERO
		_vm_holder.scale = Vector3.ONE * VM_SCALE
		for mi in _weapon_node.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_anim = _weapon_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _anim:
			if _anim.has_animation("idle"):
				_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			_anim.animation_finished.connect(_on_anim_finished)
			_anim.play("draw" if _anim.has_animation("draw") else "idle")
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = weapon_mesh(id, _vis)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_weapon_node = mi
	_vm_holder.add_child(_weapon_node)
	if _anim == null:
		_vm_holder.position = Visuals.v3(_vis.offset)
		_vm_holder.scale = Vector3.ONE
	if _muzzle.get_parent():
		_muzzle.get_parent().remove_child(_muzzle)
	var marker := _weapon_node.find_child("Muzzle", true, false) as Node3D
	if marker:
		marker.add_child(_muzzle)
		_muzzle.position = Vector3.ZERO
	else:
		_vm_holder.add_child(_muzzle)
		_muzzle.position = Visuals.v3(_vis.muzzle)


## Places the camera. pos is the eye position in world space.
func set_view(pos: Vector3, yaw: float, pitch: float, moving: bool, delta: float) -> void:
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.03
	_shake = maxf(0.0, _shake - delta * 3.0)
	camera.fov = 75.0 + _fov_punch
	_fov_punch = move_toward(_fov_punch, 0.0, delta * 18.0)
	global_position = pos + Vector3(0, -_down, 0)
	rotation = Vector3(0, yaw, 0)
	camera.rotation = Vector3(pitch + shake.y, shake.x, 0)
	if moving:
		_bob_t += delta * BOB_FREQ
	else:
		_bob_t = lerpf(_bob_t, roundf(_bob_t / PI) * PI, delta * 6.0)
	_animate(delta)


func muzzle_position() -> Vector3:
	return _muzzle.global_position


func _on_anim_finished(_name: StringName) -> void:
	if _anim and _anim.has_animation("idle"):
		_anim.play("idle", 0.15)


func _play_once(anim_name: String, speed := 1.0) -> bool:
	if _anim == null or not _anim.has_animation(anim_name):
		return false
	_anim.stop()
	_anim.play(anim_name, 0.05, speed)
	return true


## A kill: the view breathes out for a moment (a few degrees of field of view).
func punch(degrees: float) -> void:
	_fov_punch = maxf(_fov_punch, degrees)


## `shake`: camera shake added by this shot (heavier guns shake more).
func on_fire(shake := 0.0) -> void:
	_shake = minf(_shake + shake, 0.6)
	_kick = 0.35 if _play_once("fire") else 1.0
	_flash_t = 0.05
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.2)
	if muzzle_light_enabled:
		_light.visible = true
		_light.light_energy = 2.5


func on_reload(duration: float) -> void:
	if _anim and _anim.has_animation("reload"):
		var length := _anim.get_animation("reload").length
		_play_once("reload", length / maxf(duration, 0.1))  # authored as 2 s, stretched to reloadSec
		return
	_reload_len = duration
	_reload_t = 0.0


func on_switch(new_weapon: String) -> void:
	_pending_weapon = new_weapon
	_switch_t = 0.0
	_reload_t = -1.0


func on_damage(amount: float) -> void:
	_shake = clampf(_shake + amount / 40.0, 0.0, 1.0)


func set_viewmodel_visible(on: bool) -> void:
	_vm_root.visible = on


## Infection mode: the infected see their own clawed hands instead of a gun.
func set_claws(on: bool) -> void:
	if on == _claws_on:
		return
	_claws_on = on
	if _claws == null:
		_claws = _build_claws()
		_vm_root.add_child(_claws)
	_claws.visible = on
	_vm_holder.visible = not on
	_flash.visible = false
	_light.visible = false


## A claw swing (the server decides whether it lands).
func on_claw() -> void:
	_claw_t = 0.0
	_kick = 0.6


static func _build_claws() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.47, 0.36)
	mat.roughness = 0.95
	var nail := StandardMaterial3D.new()
	nail.albedo_color = Color(0.12, 0.1, 0.08)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.045
		cap.height = 0.42
		arm.mesh = cap
		arm.material_override = mat
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.position = Vector3(0.22 * side, -0.2, -0.32)
		arm.rotation = Vector3(deg_to_rad(-70), deg_to_rad(12 * side), 0)
		arm.name = "ArmL" if side < 0 else "ArmR"
		root.add_child(arm)
		for i in 3:
			var c := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.012
			cone.height = 0.07
			c.mesh = cone
			c.material_override = nail
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.position = Vector3(0.22 * side + (i - 1) * 0.03, -0.09, -0.5)
			c.rotation = Vector3(deg_to_rad(-100), 0, 0)
			root.add_child(c)
	return root


func set_downed(downed: bool) -> void:
	_down = 1.0 if downed else 0.0
	_vm_root.visible = not downed


func _animate(delta: float) -> void:
	_kick = maxf(0.0, _kick - delta * 12.0)
	var kick_amt: float = _vis.get("recoilKick", 0.04)
	var pos := Vector3(sin(_bob_t * 0.5) * BOB_AMP, -absf(sin(_bob_t)) * BOB_AMP, _kick * kick_amt)
	var rot := Vector3(_kick * 0.12, 0, 0)
	if _reload_t >= 0.0:
		_reload_t += delta
		var k := clampf(_reload_t / _reload_len, 0.0, 1.0)
		var dip := sin(k * PI)
		pos += Vector3(0, -0.07 * dip, 0.02 * dip)
		rot += Vector3(-0.5 * dip, 0, 0.6 * dip)
		if k >= 1.0:
			_reload_t = -1.0
	if _switch_t >= 0.0:
		_switch_t += delta
		var half := 0.22
		if _switch_t < half:
			pos.y -= 0.25 * (_switch_t / half)
		else:
			if _pending_weapon != "":
				set_weapon(_pending_weapon)
				_pending_weapon = ""
				if _anim:  # the model's draw animation brings it up
					_switch_t = -1.0
			pos.y -= 0.25 * (1.0 - clampf((_switch_t - half) / half, 0.0, 1.0))
			if _switch_t > half * 2.0:
				_switch_t = -1.0
	if _claws_on and _claws:
		# swing: both hands lunge forward and down, then come back
		if _claw_t >= 0.0:
			_claw_t += delta
			var k := clampf(_claw_t / 0.32, 0.0, 1.0)
			var s := sin(k * PI)
			_claws.position = Vector3(0, -0.12 * s, -0.22 * s)
			_claws.rotation = Vector3(-0.5 * s, 0, 0)
			if k >= 1.0:
				_claw_t = -1.0
		else:
			_claws.position = Vector3(0, 0.01 * sin(_bob_t * 0.5), 0)
			_claws.rotation = Vector3.ZERO
	_vm_root.position = pos
	_vm_root.rotation = rot
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
			_light.visible = false
		else:
			_light.light_energy = 2.5 * (_flash_t / 0.05)


static func weapon_mesh(id: String, v: Dictionary = {}) -> ArrayMesh:
	if v.is_empty():
		v = Visuals.weapon(id)
	if _weapon_mesh_cache.has(id):
		return _weapon_mesh_cache[id]
	var body := MeshKit.mat(Color(v.body), 0.5)
	body.metallic = 0.4
	var accent := MeshKit.mat(Color(v.accent), 0.6)
	var glove := MeshKit.mat(Color(v.glove), 0.9)
	var parts := []
	if v.shape == "pistol":
		parts = [
			{"mesh": MeshKit.box(Vector3(0.036, 0.04, 0.2)), "xform": MeshKit.xf(Vector3(0, 0.035, -0.08)), "mat": 0},
			{"mesh": MeshKit.box(Vector3(0.032, 0.03, 0.17)), "xform": MeshKit.xf(Vector3(0, 0.005, -0.07)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.03, 0.11, 0.05)), "xform": MeshKit.xf(Vector3(0, -0.04, 0.0), Vector3(-0.25, 0, 0)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.06, 0.07, 0.09)), "xform": MeshKit.xf(Vector3(0.0, -0.05, 0.03), Vector3(-0.25, 0, 0)), "mat": 2},
		]
	elif v.shape == "shotgun":
		parts = [
			{"mesh": MeshKit.box(Vector3(0.055, 0.075, 0.3)), "xform": MeshKit.xf(Vector3(0, 0.0, -0.1)), "mat": 0},
			{"mesh": MeshKit.cylinder(0.018, 0.42), "xform": MeshKit.xf(Vector3(0, 0.02, -0.42), Vector3(PI / 2, 0, 0)), "mat": 0},
			{"mesh": MeshKit.cylinder(0.022, 0.2), "xform": MeshKit.xf(Vector3(0, -0.02, -0.36), Vector3(PI / 2, 0, 0)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.045, 0.09, 0.2)), "xform": MeshKit.xf(Vector3(0, -0.025, 0.13), Vector3(-0.1, 0, 0)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.06, 0.07, 0.09)), "xform": MeshKit.xf(Vector3(0, -0.06, 0.0), Vector3(-0.2, 0, 0)), "mat": 2},
			{"mesh": MeshKit.box(Vector3(0.06, 0.06, 0.09)), "xform": MeshKit.xf(Vector3(-0.01, -0.05, -0.36)), "mat": 2},
		]
	elif v.shape == "smg":
		parts = [
			{"mesh": MeshKit.box(Vector3(0.045, 0.065, 0.24)), "xform": MeshKit.xf(Vector3(0, 0.0, -0.08)), "mat": 0},
			{"mesh": MeshKit.cylinder(0.014, 0.12), "xform": MeshKit.xf(Vector3(0, 0.012, -0.26), Vector3(PI / 2, 0, 0)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.03, 0.16, 0.04)), "xform": MeshKit.xf(Vector3(0, -0.1, -0.06)), "mat": 0},
			{"mesh": MeshKit.box(Vector3(0.02, 0.05, 0.16)), "xform": MeshKit.xf(Vector3(0, -0.005, 0.12)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.06, 0.07, 0.09)), "xform": MeshKit.xf(Vector3(0, -0.06, 0.02), Vector3(-0.2, 0, 0)), "mat": 2},
		]
	else:
		parts = [
			{"mesh": MeshKit.box(Vector3(0.05, 0.07, 0.34)), "xform": MeshKit.xf(Vector3(0, 0.0, -0.12)), "mat": 0},
			{"mesh": MeshKit.cylinder(0.012, 0.22), "xform": MeshKit.xf(Vector3(0, 0.015, -0.39), Vector3(PI / 2, 0, 0)), "mat": 0},
			{"mesh": MeshKit.box(Vector3(0.045, 0.06, 0.16)), "xform": MeshKit.xf(Vector3(0, 0.0, -0.28)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.04, 0.08, 0.18)), "xform": MeshKit.xf(Vector3(0, -0.015, 0.12)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.035, 0.12, 0.055)), "xform": MeshKit.xf(Vector3(0, -0.08, -0.12), Vector3(0.2, 0, 0)), "mat": 0},
			{"mesh": MeshKit.box(Vector3(0.02, 0.03, 0.08)), "xform": MeshKit.xf(Vector3(0, 0.05, -0.08)), "mat": 1},
			{"mesh": MeshKit.box(Vector3(0.06, 0.07, 0.09)), "xform": MeshKit.xf(Vector3(0, -0.06, 0.0), Vector3(-0.2, 0, 0)), "mat": 2},
			{"mesh": MeshKit.box(Vector3(0.06, 0.06, 0.09)), "xform": MeshKit.xf(Vector3(-0.01, -0.04, -0.27)), "mat": 2},
		]
	_weapon_mesh_cache[id] = MeshKit.merge(parts, [body, accent, glove])
	return _weapon_mesh_cache[id]


static func _flash_mesh() -> QuadMesh:
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.7, 1))
	g.set_color(1, Color(1, 0.5, 0.1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	q.material = m
	return q
