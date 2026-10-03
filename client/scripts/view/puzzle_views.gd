class_name PuzzleViews
extends Node3D
## The puzzle objects of an online zone (phase 31), drawn from what the server
## sends (Net.puzzles). The client knows nothing of the rules: each kind is a
## generic prop whose look follows its state. Kinds (protocol puzzleKind):
## text (painted on a wall), lantern (on a pole; shot at), terminal (keypad),
## lever, cage (electric), canister (carried on a player's back), transmitter
## (mast and cabinet) and case (the reward crate).

const TEXT := 0
const LANTERN := 1
const TERMINAL := 2
const LEVER := 3
const CAGE := 4
const CANISTER := 5
const TRANSMITTER := 6
const CASE := 7

## entity id -> world position of that player's back (carried canisters)
var carrier_pos: Callable = func(_id: int) -> Variant: return null

var _views := {}  ## id -> {node, kind, mats: Dictionary, light}
var _t := 0.0
static var _mats := {}


func _ready() -> void:
	Net.puzzles_changed.connect(_rebuild)
	Net.puzzle_state.connect(_on_state)
	_rebuild()


func _exit_tree() -> void:
	if Net.puzzles_changed.is_connected(_rebuild):
		Net.puzzles_changed.disconnect(_rebuild)
	if Net.puzzle_state.is_connected(_on_state):
		Net.puzzle_state.disconnect(_on_state)


## The object a player standing at `pos` (sim x, z) can use, or {}.
func usable_near(pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for o in Net.puzzles.values():
		if str(o.label) == "" or float(o.useRadius) <= 0.0:
			continue
		var d := pos.distance_to(Vector2(float(o.x), float(o.z)))
		if d <= float(o.useRadius) and d < best_d:
			best = o
			best_d = d
	return best


func _rebuild() -> void:
	var seen := {}
	for id in Net.puzzles:
		seen[id] = true
		var o: Dictionary = Net.puzzles[id]
		if not _views.has(id):
			_views[id] = _build(o)
			add_child(_views[id].node)
		var v: Dictionary = _views[id]
		v.node.position = Vector3(float(o.x), float(o.y), float(o.z))
		v.node.rotation.y = float(o.yaw)
		_apply(id)
	for id in _views.keys():
		if not seen.has(id):
			_views[id].node.queue_free()
			_views.erase(id)
	print("[puzzle] %d objects" % _views.size())


func _on_state(id: int) -> void:
	_apply(id)


func _process(delta: float) -> void:
	_t += delta
	for id in _views:
		var v: Dictionary = _views[id]
		var o: Dictionary = Net.puzzles.get(id, {})
		if o.is_empty():
			continue
		match int(v.kind):
			CAGE:
				if int(o.state) == 1:
					# live: the bars flicker like an arc
					var e := 2.2 + 1.6 * absf(sin(_t * 23.0)) * (0.5 + 0.5 * sin(_t * 7.0))
					(v.mats.bar as StandardMaterial3D).emission_energy_multiplier = e
			TRANSMITTER:
				var s := int(o.state)
				var tip: StandardMaterial3D = v.mats.tip
				var e := 0.0
				if s == 1:
					e = 4.0 if fmod(_t, 1.2) < 0.3 else 0.6
				elif s == 2:
					e = 3.0 + 3.0 * absf(sin(_t * 9.0))
				tip.emission_energy_multiplier = e
			CANISTER:
				var carrier := int(o.state)
				if carrier > 0:
					var at: Variant = carrier_pos.call(carrier)
					if at != null:
						v.node.global_position = v.node.global_position.lerp(at, minf(1.0, delta * 20.0))
						v.node.rotation.y += delta * 2.0
				else:
					v.node.position = Vector3(float(o.x), float(o.y) + 0.05 * sin(_t * 2.0), float(o.z))
			TEXT:
				var lab: Label3D = v.label
				var want := 0.92 if int(o.state) == 1 else 0.0
				lab.modulate.a = move_toward(lab.modulate.a, want, delta * 1.5)
				lab.visible = lab.modulate.a > 0.01


func _apply(id: int) -> void:
	var v: Dictionary = _views.get(id, {})
	var o: Dictionary = Net.puzzles.get(id, {})
	if v.is_empty() or o.is_empty():
		return
	var s := int(o.state)
	match int(v.kind):
		TEXT:
			(v.label as Label3D).text = str(o.text)
		LANTERN:
			var core: StandardMaterial3D = v.mats.core
			core.emission_energy_multiplier = [0.0, 1.6, 9.0][clampi(s, 0, 2)]
			core.emission = Color(1.0, 0.62, 0.25) if s < 2 else Color(1.0, 0.92, 0.7)
			var light: OmniLight3D = v.light
			light.visible = s == 2
		TERMINAL:
			var screen: StandardMaterial3D = v.mats.screen
			screen.emission = [Color(0.05, 0.05, 0.05), Color(0.25, 0.95, 0.45), Color(1.0, 0.18, 0.12)][clampi(s, 0, 2)]
			screen.emission_energy_multiplier = 0.2 if s == 0 else 2.2
		LEVER:
			(v.handle as Node3D).rotation.x = deg_to_rad(-40.0 if s == 0 else 40.0)
			(v.mats.lamp as StandardMaterial3D).emission_energy_multiplier = 3.0 if s == 1 else 0.3
		CAGE:
			if s == 0:
				(v.mats.bar as StandardMaterial3D).emission_energy_multiplier = 0.0
			(v.light as OmniLight3D).visible = s == 1
		CASE:
			(v.mats.glow as StandardMaterial3D).emission_energy_multiplier = 3.5 if s == 1 else 0.0
			(v.lid as Node3D).rotation.x = deg_to_rad(-70.0 if s == 1 else 0.0)


# ------------------------------------------------------------------ props

static func _mat(key: String, color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


static func _glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build(o: Dictionary) -> Dictionary:
	var root := Node3D.new()
	var v := {"node": root, "kind": int(o.kind), "mats": {}}
	var iron := _mat("iron", Color(0.12, 0.12, 0.13), 0.55, 0.6)
	var dark := _mat("dark", Color(0.06, 0.06, 0.07), 0.7, 0.3)
	match int(o.kind):
		TEXT:
			var l := Label3D.new()
			l.font = UiTheme.display_font()
			l.font_size = 96
			l.pixel_size = float(o.size) / 96.0 * 1.1
			l.modulate = Color(0.5, 0.02, 0.03, 0.0)
			l.outline_size = 0
			l.double_sided = false
			l.shaded = false
			l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.line_spacing = -20.0
			# the node's -Z is the way the reader looks (yaw from the server): the
			# label's face (+Z) points back at them
			root.add_child(l)
			v.label = l
		LANTERN:
			_part(root, MeshKit.cylinder(0.035, 2.0), iron, Vector3(0, 1.0, 0))
			_part(root, MeshKit.box(Vector3(0.26, 0.04, 0.26)), iron, Vector3(0, 2.32, 0))
			_part(root, MeshKit.box(Vector3(0.22, 0.03, 0.22)), iron, Vector3(0, 1.94, 0))
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				_part(root, MeshKit.box(Vector3(0.02, 0.36, 0.02)), iron, Vector3(c.x * 0.1, 2.13, c.y * 0.1))
			var core := _glow(Color(1.0, 0.62, 0.25), 0.0)
			_part(root, MeshKit.box(Vector3(0.15, 0.28, 0.15)), core, Vector3(0, 2.12, 0))
			v.mats.core = core
			var light := OmniLight3D.new()
			light.position = Vector3(0, 2.1, 0)
			light.light_color = Color(1.0, 0.85, 0.6)
			light.light_energy = 2.5
			light.omni_range = 5.0
			light.shadow_enabled = false
			light.visible = false
			root.add_child(light)
			v.light = light
		TERMINAL:
			_part(root, MeshKit.box(Vector3(0.55, 1.05, 0.38)), dark, Vector3(0, 0.525, 0))
			_part(root, MeshKit.box(Vector3(0.6, 0.06, 0.44)), iron, Vector3(0, 1.08, 0))
			var screen := _glow(Color(0.25, 0.95, 0.45), 2.2)
			_part(root, MeshKit.box(Vector3(0.4, 0.28, 0.02)), screen, Vector3(0, 0.82, -0.2), Vector3(-0.25, 0, 0))
			_part(root, MeshKit.box(Vector3(0.36, 0.03, 0.16)), iron, Vector3(0, 0.6, -0.24), Vector3(0.5, 0, 0))
			v.mats.screen = screen
		LEVER:
			_part(root, MeshKit.box(Vector3(0.35, 0.5, 0.12)), dark, Vector3(0, 1.0, 0))
			var pivot := Node3D.new()
			pivot.position = Vector3(0, 1.0, -0.08)
			root.add_child(pivot)
			_part(pivot, MeshKit.cylinder(0.025, 0.42), iron, Vector3(0, 0.21, 0))
			_part(pivot, MeshKit.box(Vector3(0.12, 0.06, 0.06)), _mat("redgrip", Color(0.45, 0.05, 0.04), 0.6), Vector3(0, 0.43, 0))
			v.handle = pivot
			var lamp := _glow(Color(1.0, 0.6, 0.15), 0.3)
			_part(root, MeshKit.box(Vector3(0.06, 0.06, 0.03)), lamp, Vector3(0.12, 1.2, -0.07))
			v.mats.lamp = lamp
			_part(root, MeshKit.cylinder(0.04, 1.0), iron, Vector3(0, 0.5, 0.0))
		CAGE:
			var s := float(o.size)
			var bar := _glow(Color(0.55, 0.8, 1.0), 0.0)
			bar.albedo_color = Color(0.1, 0.11, 0.13)
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				_part(root, MeshKit.cylinder(0.07, 2.8), iron, Vector3(c.x * s, 1.4, c.y * s))
			for side in 4:
				var a := side * PI / 2.0
				var dir := Vector3(cos(a), 0, sin(a))
				var along := Vector3(-sin(a), 0, cos(a))
				_part(root, MeshKit.box(Vector3(0.08, 0.08, 2.0 * s)), iron, dir * s + Vector3(0, 2.8, 0), Vector3(0, -a, 0))
				var n := int(s * 2.0 / 0.6)
				for i in range(1, n):
					var t := -s + i * (2.0 * s / n)
					_part(root, MeshKit.cylinder(0.02, 2.7), bar, dir * s + along * t + Vector3(0, 1.35, 0))
			var light := OmniLight3D.new()
			light.position = Vector3(0, 2.0, 0)
			light.light_color = Color(0.55, 0.8, 1.0)
			light.light_energy = 2.0
			light.omni_range = s * 3.0
			light.visible = false
			root.add_child(light)
			v.mats.bar = bar
			v.light = light
		CANISTER:
			_part(root, MeshKit.cylinder(0.13, 0.46), iron, Vector3(0, 0.23, 0))
			var band := _glow(Color(0.3, 1.0, 0.55), 2.5)
			_part(root, MeshKit.cylinder(0.135, 0.18), band, Vector3(0, 0.23, 0))
			_part(root, MeshKit.cylinder(0.05, 0.06), iron, Vector3(0, 0.49, 0))
		TRANSMITTER:
			_part(root, MeshKit.box(Vector3(1.0, 1.4, 0.7)), dark, Vector3(0, 0.7, 0))
			_part(root, MeshKit.box(Vector3(1.06, 0.08, 0.76)), iron, Vector3(0, 1.42, 0))
			_part(root, MeshKit.cylinder(0.06, 4.2), iron, Vector3(0, 3.5, 0))
			for i in 4:
				_part(root, MeshKit.box(Vector3(0.9 - i * 0.18, 0.03, 0.03)), iron, Vector3(0, 2.4 + i * 0.75, 0))
			var tip := _glow(Color(1.0, 0.25, 0.12), 0.0)
			_part(root, MeshKit.box(Vector3(0.14, 0.14, 0.14)), tip, Vector3(0, 5.65, 0))
			v.mats.tip = tip
			var dial := _glow(Color(1.0, 0.7, 0.3), 1.2)
			_part(root, MeshKit.box(Vector3(0.5, 0.2, 0.02)), dial, Vector3(0, 1.05, -0.36))
		CASE:
			_part(root, MeshKit.box(Vector3(1.1, 0.42, 0.6)), dark, Vector3(0, 0.21, 0))
			var glow := _glow(Color(1.0, 0.4, 0.12), 0.0)
			_part(root, MeshKit.box(Vector3(0.9, 0.05, 0.42)), glow, Vector3(0, 0.43, 0))
			var lid := Node3D.new()
			lid.position = Vector3(0, 0.44, 0.3)
			root.add_child(lid)
			_part(lid, MeshKit.box(Vector3(1.12, 0.08, 0.62)), iron, Vector3(0, 0.04, -0.3))
			v.mats.glow = glow
			v.lid = lid
	return v
