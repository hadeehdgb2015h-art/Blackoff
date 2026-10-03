class_name SkyVisions
extends MeshInstance3D
## Sky visions (phase 21): every half minute or so a vision fades in beside
## the moon, lingers, and fades out; the next one appears on the other side.
## Six original scenes (art/blender/build_visions.py): the moon over a sea of
## statues, a whale in the clouds, the glowing tree, the lantern keeper, the
## watcher's eye and the game's name. Cost: one additive quad, one 512 px
## texture in memory (loaded when its turn comes, released after).

const SCENES := ["moon_sea", "sky_whale", "glow_tree", "lantern_keeper", "watcher", "logo"]
## per scene brightness (the name and the bright moon are dimmed so they do not wash out)
const ENERGY := {"logo": 0.7, "moon_sea": 0.85}
const FADE_IN := 3.5
const HOLD := 10.0
const FADE_OUT := 3.5

var _mat: ShaderMaterial
var _moon: Vector3
var _size: float
var _order: Array = []
var _side: float = 1.0
var _t: float = 0.0
var _wait: float = 14.0      ## seconds until the next vision (the first comes soon)
var _showing: bool = false


## Added as a child of the moon quad (top level: it places itself beside it).
## `moon_size`: the moon's quad size (metres).
func setup(moon_size: float) -> void:
	_size = moon_size * 3.8
	var q := QuadMesh.new()
	q.size = Vector2.ONE * _size
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/fx_vision.gdshader")
	_mat.set_shader_parameter("fade", 0.0)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0
	visible = false
	if Platform.query_param("vision") != "":  # screenshot tests: one at once
		_order = [Platform.query_param("vision")]
		_wait = 0.5


func _process(delta: float) -> void:
	if not _showing:
		_wait -= delta
		if _wait <= 0.0:
			_begin()
		return
	_t += delta
	var k := 1.0
	if _t < FADE_IN:
		k = smoothstep(0.0, 1.0, _t / FADE_IN)
	elif _t > FADE_IN + HOLD:
		k = 1.0 - smoothstep(0.0, 1.0, (_t - FADE_IN - HOLD) / FADE_OUT)
	_mat.set_shader_parameter("fade", k)
	if _t >= FADE_IN + HOLD + FADE_OUT:
		_end()


func _begin() -> void:
	if _order.is_empty():
		_order = SCENES.duplicate()
		_order.shuffle()
	var name: String = _order.pop_front()
	var path := "res://assets/textures/sky_vision_%s.png" % name
	if not ResourceLoader.exists(path):
		_wait = 30.0
		return
	_mat.set_shader_parameter("tex", load(path))
	_mat.set_shader_parameter("energy", 1.5 * float(ENERGY.get(name, 1.0)))
	# beside the moon, alternating sides, a little above or below it
	_moon = (get_parent() as Node3D).global_position
	var to_moon := Vector3(_moon.x, 0.0, _moon.z).normalized()
	var right := Vector3.UP.cross(to_moon).normalized()
	_side = -_side
	var spot := _moon + right * _side * (_size * 0.5) + Vector3.UP * randf_range(0.42, 0.55) * _size
	# keep the moon's distance from the map: farther would pass the camera's far plane (480 m on low)
	position = spot.normalized() * _moon.length()
	_t = 0.0
	_showing = true
	visible = true


func _end() -> void:
	_showing = false
	visible = false
	_mat.set_shader_parameter("tex", null)  # free the texture until the next turn
	_wait = randf_range(20.0, 32.0)
