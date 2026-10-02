class_name Atmosphere
extends Node3D
## Dark-fantasy atmosphere, purely visual. Builds effects at the map's
## `map_fx` markers (meta "fx" = kind) and animates them:
##   sigil  glowing quad (rune circle, glyph, corruption veins), marker +Z = facing
##   motes  drifting glowing dust (box volume)
##   mist   scrolling ground mist sheet
##   fire   brazier flames, embers and a flickering light
##   shaft  fake volumetric light cone under a lamp
##   rift   floating crystal with orbiting rune rings (the outbreak centrepiece)
## Lights in group `map_light` with meta "flicker" ("fire" or "pulse") are animated too.
## Run after MapBatcher (FX meshes are not batched).

const TEX := {
	"rune_circle": "res://assets/textures/fx_rune_circle.png",
	"glyphs": "res://assets/textures/fx_glyphs.png",
	"veins": "res://assets/textures/fx_veins.png",
	"mist": "res://assets/textures/fx_mist.png",
}
const SH_GLOW := "res://shaders/fx_glow.gdshader"
const SH_MIST := "res://shaders/fx_mist.gdshader"
const SH_SHAFT := "res://shaders/fx_shaft.gdshader"

var _flicker: Array = []   ## [light, base_energy, mode, seed]
var _spinners: Array = []  ## [node, axis, speed]
var _bobbers: Array = []   ## [node, base_y, amplitude, speed, seed]
var _motes: Array[CPUParticles3D] = []
var _optional: Array[Node3D] = []  ## mist and shafts: hidden on the low tier
var _t: float = 0.0
var _soft: Texture2D


static func build(map_root: Node3D) -> Atmosphere:
	var a := Atmosphere.new()
	a.name = "Atmosphere"
	map_root.add_child(a)
	a._build(map_root)
	return a


func set_quality(q: String) -> void:
	for n in _optional:
		n.visible = q != "low"
	for p in _motes:
		p.amount = maxi(4, int(p.get_meta("full_amount") * (0.4 if q == "low" else 1.0)))


func _build(map_root: Node3D) -> void:
	_soft = _soft_dot()
	var stack: Array[Node] = [map_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.is_in_group("map_fx"):
			_make(n as Node3D, map_root)
		elif n is Light3D and n.is_in_group("map_light") and n.has_meta("flicker"):
			_flicker.append([n, (n as Light3D).light_energy, str(n.get_meta("flicker")), randf() * 100.0])


func _make(m: Node3D, map_root: Node3D) -> void:
	var xf := map_root.global_transform.affine_inverse() * m.global_transform
	var node: Node3D
	match str(m.get_meta("fx")):
		"sigil":
			node = _sigil(m)
		"motes":
			node = _motes_fx(m)
		"mist":
			node = _mist(m)
			_optional.append(node)
		"fire":
			node = _fire(m)
		"shaft":
			node = _shaft(m)
			_optional.append(node)
		"rift":
			node = _rift(m)
		_:
			push_warning("Atmosphere: unknown fx " + str(m.get_meta("fx")))
			return
	node.transform = xf
	add_child(node)


# ------------------------------------------------------------ kinds

func _glow_material(tex_key: String, color: Color, energy: float, spin := 0.0, pulse := 0.25, cell := -1) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SH_GLOW)
	mat.set_shader_parameter("tex", load(TEX[tex_key]))
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("spin", spin)
	mat.set_shader_parameter("pulse", pulse)
	mat.set_shader_parameter("pulse_speed", randf_range(1.1, 1.9))
	mat.set_shader_parameter("phase", randf() * TAU)
	if cell >= 0:
		mat.set_shader_parameter("atlas", Vector4((cell % 4) * 0.25, (cell / 4) * 0.25, 0.25, 0.25))
	return mat


func _quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sigil(m: Node3D) -> Node3D:
	var mat := _glow_material(str(m.get_meta("tex", "rune_circle")), m.get_meta("color", Color(0.7, 0.35, 1.0)),
		float(m.get_meta("energy", 1.5)), float(m.get_meta("spin", 0.0)), float(m.get_meta("pulse", 0.25)), int(m.get_meta("cell", -1)))
	return _quad(m.get_meta("size", Vector2.ONE), mat)


func _motes_fx(m: Node3D) -> Node3D:
	var color: Color = m.get_meta("color", Color(0.75, 0.45, 1.0))
	var p := _particles(int(m.get_meta("amount", 30)), 7.0, 0.07, color * 2.2)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = m.get_meta("extents", Vector3(4, 1, 4))
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.18
	p.gravity = Vector3(0, 0.05, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.preprocess = 7.0
	p.set_meta("full_amount", p.amount)
	_motes.append(p)
	return p


func _mist(m: Node3D) -> Node3D:
	var mat := ShaderMaterial.new()
	mat.shader = load(SH_MIST)
	mat.set_shader_parameter("noise_tex", load(TEX.mist))
	mat.set_shader_parameter("color", m.get_meta("color", Color(0.55, 0.42, 0.78, 0.4)))
	mat.set_shader_parameter("speed", float(m.get_meta("speed", 1.0)))
	return _quad(m.get_meta("size", Vector2(10, 10)), mat)


func _fire(m: Node3D) -> Node3D:
	var root := Node3D.new()
	var flames := _particles(26, 0.65, 0.42, Color(1, 1, 1))
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.17
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.initial_velocity_min = 0.5
	flames.initial_velocity_max = 1.0
	flames.gravity = Vector3(0, 1.4, 0)
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.1
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.7))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.15))
	flames.scale_amount_curve = sc
	flames.color_ramp = _ramp([
		[0.0, Color(2.4, 1.7, 0.8, 0.0)], [0.12, Color(2.6, 1.4, 0.45, 1.0)],
		[0.55, Color(1.8, 0.45, 0.12, 0.7)], [1.0, Color(0.4, 0.06, 0.12, 0.0)]])
	root.add_child(flames)
	var embers := _particles(10, 1.8, 0.05, Color(3.0, 1.2, 0.35))
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.2
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 0.8
	embers.initial_velocity_max = 1.6
	embers.gravity = Vector3(0, 0.3, 0)
	embers.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.7, Color(1, 0.6, 0.4, 0.8)], [1.0, Color(1, 0.3, 0.2, 0)]])
	root.add_child(embers)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.light_energy = float(m.get_meta("energy", 2.2))
	light.omni_range = float(m.get_meta("range", 7.0))
	light.omni_attenuation = 1.3
	light.position = Vector3(0, 0.5, 0)
	root.add_child(light)
	_flicker.append([light, light.light_energy, "fire", randf() * 100.0])
	return root


func _shaft(m: Node3D) -> Node3D:
	var h := float(m.get_meta("height", 2.6))
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(m.get_meta("top", 0.25))
	cyl.bottom_radius = float(m.get_meta("bottom", 1.3))
	cyl.height = h
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 16
	cyl.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = load(SH_SHAFT)
	mat.set_shader_parameter("color", m.get_meta("color", Color(1.0, 0.85, 0.6)))
	mat.set_shader_parameter("energy", float(m.get_meta("energy", 0.18)))
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = -h / 2.0  # marker sits at the lamp, the cone hangs below it
	var root := Node3D.new()
	root.add_child(mi)
	return root


func _rift(m: Node3D) -> Node3D:
	var color: Color = m.get_meta("color", Color(1.0, 0.35, 0.9))
	var root := Node3D.new()
	var float_node := Node3D.new()  # bobs; root keeps the marker transform
	root.add_child(float_node)
	var crystal_mat := StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(0.25, 0.05, 0.3)
	crystal_mat.emission_enabled = true
	crystal_mat.emission = color
	crystal_mat.emission_energy_multiplier = 2.6
	crystal_mat.roughness = 0.25
	crystal_mat.metallic = 0.4
	var core := MeshInstance3D.new()
	core.mesh = _shard_mesh(0.9, 0.34)
	core.material_override = crystal_mat
	float_node.add_child(core)
	_spinners.append([core, Vector3.UP, 0.7])
	_bobbers.append([float_node, 0.0, 0.12, 1.3, 0.0])
	for i in 3:  # small shards orbiting the core
		var pivot := Node3D.new()
		pivot.rotation.y = i * TAU / 3.0
		var shard := MeshInstance3D.new()
		shard.mesh = _shard_mesh(0.28, 0.1)
		shard.material_override = crystal_mat
		shard.position = Vector3(1.05, 0.15 * (i - 1), 0)
		shard.rotation.z = 0.4
		pivot.add_child(shard)
		float_node.add_child(pivot)
		_spinners.append([pivot, Vector3.UP, -0.9])
	var ring_a := _quad(Vector2(3.0, 3.0), _glow_material("rune_circle", color, 1.3, 0.35, 0.2))
	ring_a.rotation.x = -PI / 2
	float_node.add_child(ring_a)
	var gimbal := Node3D.new()
	var ring_b := _quad(Vector2(2.3, 2.3), _glow_material("rune_circle", Color(0.6, 0.4, 1.0), 1.1, -0.5, 0.2))
	gimbal.add_child(ring_b)
	gimbal.rotation.x = 0.35
	float_node.add_child(gimbal)
	_spinners.append([gimbal, Vector3.UP, 0.45])
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 7.5
	light.omni_attenuation = 1.4
	root.add_child(light)
	_flicker.append([light, light.light_energy, "pulse", 0.0])
	return root


# ------------------------------------------------------------ helpers

func _particles(amount: int, lifetime: float, size: float, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft
	mat.disable_fog = true  # fog would tint the whole additive quad
	q.material = mat
	p.mesh = q
	p.amount = amount
	p.lifetime = lifetime
	p.color = color
	p.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.25, Color(1, 1, 1, 1)], [0.75, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	return g


static func _soft_dot() -> Texture2D:
	var t := GradientTexture2D.new()
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.gradient = _ramp([[0.0, Color(1, 1, 1, 1)], [0.35, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0)]])
	return t


## Elongated octahedron with flat shading.
static func _shard_mesh(half_h: float, r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, half_h, 0)
	var bot := Vector3(0, -half_h * 0.8, 0)
	var ring: Array[Vector3] = []
	for i in 5:
		var a := i * TAU / 5.0
		ring.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for i in 5:
		var a := ring[i]
		var b := ring[(i + 1) % 5]
		for tri in [[top, b, a], [bot, a, b]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _process(delta: float) -> void:
	_t += delta
	for f in _flicker:
		var l: Light3D = f[0]
		var s: float = f[3]
		var k: float
		if f[2] == "fire":
			k = 0.82 + 0.1 * sin(_t * 13.0 + s) + 0.06 * sin(_t * 23.7 + s * 2.0) + 0.04 * sin(_t * 41.0)
		else:
			k = 0.8 + 0.2 * sin(_t * 1.6 + s)
		l.light_energy = f[1] * k
	for sp in _spinners:
		(sp[0] as Node3D).rotate(sp[1], sp[2] * delta)
	for b in _bobbers:
		var n: Node3D = b[0]
		n.position.y = b[1] + sin(_t * b[3] + b[4]) * b[2]
