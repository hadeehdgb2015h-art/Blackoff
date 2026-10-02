class_name Effects
extends Node3D
## Pooled cheap combat effects: bullet tracers and impact puffs.

const TRACERS := 12
const IMPACTS := 16

var _tracers: Array[MeshInstance3D] = []
var _tracer_t: PackedFloat32Array = []
var _impacts: Array[MeshInstance3D] = []
var _impact_t: PackedFloat32Array = []
var _impact_next: int = 0
var _tracer_next: int = 0
var _mat_dust: StandardMaterial3D
var _mat_blood: StandardMaterial3D
var _tracer_mats := {}  ## colour -> material (energy weapons)
var _blasts: Array[MeshInstance3D] = []
var _blast_t: PackedFloat32Array = []
var _blast_next: int = 0


func _ready() -> void:
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.85, 0.5)
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(0.012, 0.012, 1.0)
	tmesh.material = tm
	for i in TRACERS:
		var mi := MeshInstance3D.new()
		mi.mesh = tmesh
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tracers.append(mi)
		_tracer_t.append(0.0)
	var cone := CylinderMesh.new()  # cone: wide far end, narrow at the muzzle
	cone.top_radius = 0.05
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 16
	cone.rings = 1
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.albedo_color = Color(0.7, 0.9, 1.0, 0.35)
	cm.disable_fog = true
	cone.material = cm
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_blasts.append(mi)
		_blast_t.append(0.0)
	_mat_dust = _puff_mat(Color(0.75, 0.72, 0.65, 0.8))
	_mat_blood = _puff_mat(Color(0.45, 0.04, 0.03, 0.9))
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.25)
	for i in IMPACTS:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_impacts.append(mi)
		_impact_t.append(0.0)


## Energy-weapon bolt: a full-length coloured streak that lingers a little.
func bolt(from: Vector3, to: Vector3, color: Color) -> void:
	var len := from.distance_to(to)
	if len < 0.3:
		return
	var mi := _tracers[_tracer_next]
	_tracer_t[_tracer_next] = 0.12
	_tracer_next = (_tracer_next + 1) % TRACERS
	if not _tracer_mats.has(color):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.disable_fog = true
		_tracer_mats[color] = m
	mi.material_override = _tracer_mats[color]
	var d := (to - from).normalized()
	mi.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT), (from + to) / 2.0)
	mi.scale = Vector3(3.0, 3.0, len)
	mi.visible = true


## Wind-cannon blast: an expanding translucent cone from the muzzle.
func blast(from: Vector3, dir: Vector3, range_m: float) -> void:
	var mi := _blasts[_blast_next]
	_blast_t[_blast_next] = 0.3
	_blast_next = (_blast_next + 1) % _blasts.size()
	var d := dir.normalized()
	var basis := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)
	# cylinder axis is Y: rotate so its narrow top points back at the muzzle
	mi.global_transform = Transform3D(basis * Basis(Vector3.RIGHT, PI / 2), from + d * range_m * 0.5)
	mi.scale = Vector3(range_m * 0.45, range_m, range_m * 0.45)
	mi.visible = true


func tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := _tracers[_tracer_next]
	mi.material_override = null
	_tracer_t[_tracer_next] = 0.05
	_tracer_next = (_tracer_next + 1) % TRACERS
	# Draw only part of the path so it reads as a streak, not a laser.
	var a := from.lerp(to, 0.15)
	var b := from.lerp(to, minf(1.0, 0.15 + 3.0 / len))
	mi.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT), (a + b) / 2.0)
	mi.scale = Vector3(1, 1, a.distance_to(b))
	mi.visible = true


func impact(point: Vector3, blood: bool) -> void:
	var mi := _impacts[_impact_next]
	_impact_t[_impact_next] = 0.22
	_impact_next = (_impact_next + 1) % IMPACTS
	mi.material_override = _mat_blood if blood else _mat_dust
	mi.global_position = point
	mi.scale = Vector3.ONE * 0.4
	mi.visible = true


func _process(delta: float) -> void:
	for i in _blasts.size():
		if _blast_t[i] > 0.0:
			_blast_t[i] -= delta
			var k := 1.0 - _blast_t[i] / 0.3
			_blasts[i].scale = Vector3(_blasts[i].scale.x, _blasts[i].scale.y, _blasts[i].scale.z) * (1.0 + delta * 2.0)
			(_blasts[i].mesh as CylinderMesh).material.albedo_color.a = 0.35 * (1.0 - k)
			if _blast_t[i] <= 0.0:
				_blasts[i].visible = false
	for i in TRACERS:
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			if _tracer_t[i] <= 0.0:
				_tracers[i].visible = false
	for i in IMPACTS:
		if _impact_t[i] > 0.0:
			_impact_t[i] -= delta
			_impacts[i].scale = Vector3.ONE * lerpf(1.4, 0.4, _impact_t[i] / 0.22)
			if _impact_t[i] <= 0.0:
				_impacts[i].visible = false


func _puff_mat(c: Color) -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m
