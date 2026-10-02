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
##   candle small flickering candle light (the candle mesh is a map prop)
##   backdrop  a far scenery node from backdrop.glb (meta "node"): mountains, castles
##   forest pine trees scattered in a ring around the map (MultiMesh)
##   moon   the grinning moon face, a far billboard
##   storm  lightning bolts in the distance with a flash; emits `thunder`
## Lights in group `map_light` with meta "flicker" ("fire" or "pulse") are animated too.
## Run after MapBatcher (FX meshes are not batched).

signal thunder(delay: float)  ## the game plays the sound

const KINDS := ["sigil", "motes", "mist", "fire", "shaft", "rift", "candle", "backdrop", "forest", "moon", "storm"]
const BACKDROP := "res://assets/models/backdrop.glb"
const SH_BILLBOARD := "res://shaders/fx_billboard.gdshader"
const TEX := {
	"rune_circle": "res://assets/textures/fx_rune_circle.png",
	"glyphs": "res://assets/textures/fx_glyphs.png",
	"veins": "res://assets/textures/fx_veins.png",
	"mist": "res://assets/textures/fx_mist.png",
	"moon": "res://assets/textures/fx_moon_face.png",
	"bolt": "res://assets/textures/fx_bolt.png",
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
var _backdrop_lib: Node
var _forest: MultiMeshInstance3D
var _forest_full: int = 0
var _moon_light: DirectionalLight3D
var _moon_energy: float = 1.0
var _bolts: Array[MeshInstance3D] = []
var _storm := false
var _next_strike: float = 6.0
var _flash: float = 0.0


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
	if _forest:
		_forest.multimesh.visible_instance_count = _forest_full / 2 if q == "low" else -1


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
		elif n is DirectionalLight3D:
			_moon_light = n
			_moon_energy = _moon_light.light_energy
	if _backdrop_lib:
		_backdrop_lib.free()
		_backdrop_lib = null


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
		"candle":
			node = _candle(m)
		"backdrop":
			node = _backdrop(m)
		"forest":
			node = _forest_fx(m)
		"moon":
			node = _moon(m)
		"storm":
			node = _storm_fx(m)
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


func _candle(m: Node3D) -> Node3D:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.35)
	light.light_energy = float(m.get_meta("energy", 0.9))
	light.omni_range = float(m.get_meta("range", 3.5))
	light.omni_attenuation = 1.5
	_flicker.append([light, light.light_energy, "fire", randf() * 100.0])
	return light


## Far scenery: never fogged (it is painted dark already) and lit by the moon
## (layer 2, like the yard).
func _far(mi: GeometryInstance3D) -> void:
	mi.layers = 1 | 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mi is MeshInstance3D and (mi as MeshInstance3D).mesh:
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i) as BaseMaterial3D
			if src:
				var mat := src.duplicate() as BaseMaterial3D
				mat.disable_fog = true
				(mi as MeshInstance3D).set_surface_override_material(i, mat)


func _backdrop_mesh(node_name: String) -> Mesh:
	if _backdrop_lib == null:
		_backdrop_lib = (load(BACKDROP) as PackedScene).instantiate()
	var mi := _backdrop_lib.find_child(node_name, true, false) as MeshInstance3D
	return mi.mesh if mi else null


func _backdrop(m: Node3D) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _backdrop_mesh(str(m.get_meta("node")))
	mi.scale = Vector3.ONE * float(m.get_meta("scale", 1.0))
	_far(mi)
	var root := Node3D.new()
	root.add_child(mi)
	return root


func _forest_fx(m: Node3D) -> Node3D:
	var mesh := _backdrop_mesh("Pine")
	var rnd := RandomNumberGenerator.new()
	rnd.seed = int(m.get_meta("seed", 5))
	var count := int(m.get_meta("count", 300))
	var r0 := float(m.get_meta("r_min", 38.0))
	var r1 := float(m.get_meta("r_max", 140.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var a := rnd.randf() * TAU
		var r := sqrt(lerpf(r0 * r0, r1 * r1, rnd.randf()))
		var s := rnd.randf_range(0.7, 1.5)
		var b := Basis(Vector3.UP, rnd.randf() * TAU).scaled(Vector3(s, s * rnd.randf_range(0.85, 1.2), s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * r, -0.3, sin(a) * r)))
	_forest = MultiMeshInstance3D.new()
	_forest.multimesh = mm
	_forest_full = count
	_far(_forest)
	for i in mesh.get_surface_count():  # MultiMesh has no per-surface override: use one material
		var src := mesh.surface_get_material(i) as BaseMaterial3D
		if src:
			var mat := src.duplicate() as BaseMaterial3D
			mat.disable_fog = true
			mesh.surface_set_material(i, mat)
	return _forest


func _moon(m: Node3D) -> Node3D:
	var mat := ShaderMaterial.new()
	mat.shader = load(SH_BILLBOARD)
	mat.set_shader_parameter("tex", load(TEX.moon))
	mat.set_shader_parameter("energy", float(m.get_meta("energy", 1.35)))
	var q := _quad(Vector2.ONE * float(m.get_meta("size", 70.0)), mat)
	q.extra_cull_margin = 100.0
	return q


func _storm_fx(m: Node3D) -> Node3D:
	_storm = true
	var root := Node3D.new()
	for i in 2:
		var mat := ShaderMaterial.new()
		mat.shader = load(SH_BILLBOARD)
		mat.set_shader_parameter("tex", load(TEX.bolt))
		mat.set_shader_parameter("white_alpha", true)
		mat.set_shader_parameter("color", Color(0.8, 0.7, 1.0))
		mat.set_shader_parameter("energy", 2.5)
		var b := _quad(Vector2(45, 90), mat)
		b.visible = false
		b.extra_cull_margin = 100.0
		root.add_child(b)
		_bolts.append(b)
	root.set_meta("radius", float(m.get_meta("radius", 230.0)))
	return root


func _strike() -> void:
	var b := _bolts[randi() % _bolts.size()]
	var radius: float = b.get_parent().get_meta("radius")
	var a := randf_range(-PI * 0.85, -PI * 0.15)  # somewhere over the northern horizon
	b.global_position = Vector3(cos(a) * radius, randf_range(55.0, 95.0), sin(a) * radius)
	b.set_meta("t", 0.0)
	b.visible = true
	_flash = 1.0
	thunder.emit(randf_range(0.6, 1.8))


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
	if _storm:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_next_strike = randf_range(9.0, 20.0)
			_strike()
		for bolt in _bolts:
			if bolt.visible:
				var bt: float = bolt.get_meta("t") + delta
				bolt.set_meta("t", bt)
				bolt.visible = bt < 0.28 and not (bt > 0.08 and bt < 0.14)  # double flicker
		if _flash > 0.0:
			_flash = maxf(_flash - delta * 3.5, 0.0)
		if _moon_light:
			_moon_light.light_energy = _moon_energy * (1.0 + _flash * 2.5)
