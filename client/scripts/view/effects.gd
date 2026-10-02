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


func tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := _tracers[_tracer_next]
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
