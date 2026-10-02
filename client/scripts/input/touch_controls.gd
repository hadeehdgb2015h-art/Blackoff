class_name TouchControls
extends Control
## Multi-touch controls (floating move stick, drag-to-aim anywhere on the
## right side, fire button that also aims while held, reload, switch,
## contextual interact/revive, pause) plus keyboard/mouse for desktop.
## Produces one PlayerIntent per sim tick via sample().

signal pause_requested

const AIM_DEG_PER_PX := 0.2
const STICK_RADIUS := 85.0
const PITCH_LIMIT := 1.35

enum Role { NONE, STICK, AIM, FIRE, BUTTON }

var yaw: float = 0.0
var pitch: float = 0.0
var interact_label: String = ""   ## set by the game; empty hides the button
var interact_ok: bool = true
var revive_available: bool = false
var enabled: bool = true

var _touches := {}  ## index -> {role, button, start, last}
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _fire_held_touch: bool = false
var _latched: int = 0
var _held_buttons := {}  ## button name -> true while a touch holds it
var _seq: int = 0
var _keys_move := Vector2.ZERO
var _mouse_fire: bool = false
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = p


func add_recoil(pitch_kick: float, yaw_jitter: float) -> void:
	pitch = clampf(pitch + pitch_kick, -PITCH_LIMIT, PITCH_LIMIT)
	yaw += yaw_jitter


func sample() -> PlayerIntent:
	var it := PlayerIntent.new()
	_seq = (_seq + 1) % 65536
	it.seq = _seq
	it.yaw = yaw
	it.pitch = pitch
	if not enabled:
		_latched = 0
		return it
	var mv := _stick_vec
	if _keys_move != Vector2.ZERO:
		mv = _keys_move.normalized()
	it.move = mv
	var b := _latched
	if _fire_held_touch or _mouse_fire:
		b |= PlayerIntent.FIRE_HELD
	for name in _held_buttons:
		b |= _bit(name)
	it.buttons = b
	_latched = 0
	return it


# ------------------------------------------------------------ layout

func _buttons() -> Dictionary:
	var s := size
	var d := {
		"fire": {"pos": Vector2(s.x - 155, s.y - 165), "r": 78.0, "label": "FIRE"},
		"reload": {"pos": Vector2(s.x - 300, s.y - 85), "r": 44.0, "label": "R"},
		"switch": {"pos": Vector2(s.x - 95, s.y - 320), "r": 44.0, "label": "SWAP"},
		"pause": {"pos": Vector2(s.x - 46, 46), "r": 30.0, "label": "II"},
	}
	if interact_label != "":
		d["interact"] = {"pos": Vector2(s.x - 300, s.y - 230), "r": 52.0, "label": "USE"}
	if revive_available:
		d["revive"] = {"pos": Vector2(s.x - 300, s.y - 230), "r": 52.0, "label": "REVIVE"}
	return d


func _stick_home() -> Vector2:
	return Vector2(175, size.y - 165)


# ------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and enabled:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				return
			_mouse_fire = event.pressed
			if event.pressed:
				_latched |= PlayerIntent.FIRE_PRESSED
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and enabled:
			_aim(event.relative * 0.6)
	elif event is InputEventKey and not event.echo:
		_on_key(event)


func _on_key(e: InputEventKey) -> void:
	var dirs := {KEY_W: Vector2(0, 1), KEY_S: Vector2(0, -1), KEY_A: Vector2(-1, 0), KEY_D: Vector2(1, 0)}
	if dirs.has(e.keycode):
		_keys_move = Vector2.ZERO
		for k in dirs:
			if Input.is_key_pressed(k):
				_keys_move += dirs[k]
		return
	if not e.pressed:
		return
	match e.keycode:
		KEY_R:
			_latched |= PlayerIntent.RELOAD
		KEY_Q:
			_latched |= PlayerIntent.SWITCH
		KEY_E:
			_latched |= PlayerIntent.INTERACT
		KEY_F:
			_latched |= PlayerIntent.REVIVE
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			pause_requested.emit()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if not enabled:
			return
		var hit := _hit_button(e.position)
		if hit != "":
			_touches[e.index] = {"role": Role.FIRE if hit == "fire" else Role.BUTTON, "button": hit, "last": e.position}
			_press(hit)
		elif e.position.x < size.x * 0.42:
			_touches[e.index] = {"role": Role.STICK, "last": e.position}
			_stick_origin = e.position
			_stick_vec = Vector2.ZERO
		else:
			_touches[e.index] = {"role": Role.AIM, "last": e.position}
		get_viewport().set_input_as_handled()
	else:
		if not _touches.has(e.index):
			return
		var t: Dictionary = _touches[e.index]
		match t.role:
			Role.STICK:
				_stick_vec = Vector2.ZERO
			Role.FIRE:
				_fire_held_touch = false
			Role.BUTTON:
				_held_buttons.erase(t.button)
		_touches.erase(e.index)
	queue_redraw()


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	var t: Dictionary = _touches[e.index]
	var delta: Vector2 = e.position - t.last
	t.last = e.position
	match t.role:
		Role.STICK:
			var off := e.position - _stick_origin
			if off.length() > STICK_RADIUS * 1.6:
				_stick_origin = e.position - off.normalized() * STICK_RADIUS * 1.6
				off = e.position - _stick_origin
			var v := off / STICK_RADIUS
			_stick_vec = Vector2(v.x, -v.y).limit_length(1.0)
		Role.AIM, Role.FIRE:
			_aim(delta)
	get_viewport().set_input_as_handled()
	queue_redraw()


func _aim(delta_px: Vector2) -> void:
	var k := deg_to_rad(AIM_DEG_PER_PX) * Settings.sensitivity
	yaw = wrapf(yaw - delta_px.x * k, -PI, PI)
	var dy := delta_px.y * k * (-1.0 if Settings.invert_y else 1.0)
	pitch = clampf(pitch - dy, -PITCH_LIMIT, PITCH_LIMIT)


func _press(name: String) -> void:
	match name:
		"fire":
			_fire_held_touch = true
			_latched |= PlayerIntent.FIRE_PRESSED
		"pause":
			pause_requested.emit()
		_:
			_held_buttons[name] = true
			_latched |= _bit(name)
	Platform.haptic("light")


func _bit(name: String) -> int:
	match name:
		"reload":
			return PlayerIntent.RELOAD
		"switch":
			return PlayerIntent.SWITCH
		"interact":
			return PlayerIntent.INTERACT
		"revive":
			return PlayerIntent.REVIVE
	return 0


func _hit_button(p: Vector2) -> String:
	var bs := _buttons()
	for name in bs:
		var b: Dictionary = bs[name]
		if p.distance_to(b.pos) <= b.r * 1.15:
			return name
	return ""


func release_all() -> void:
	_touches.clear()
	_stick_vec = Vector2.ZERO
	_fire_held_touch = false
	_held_buttons.clear()
	_mouse_fire = false
	_keys_move = Vector2.ZERO
	queue_redraw()


# ------------------------------------------------------------ drawing

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var stick_active := false
	for t in _touches.values():
		stick_active = stick_active or t.role == Role.STICK
	var base := _stick_origin if stick_active else _stick_home()
	draw_circle(base, STICK_RADIUS, Color(1, 1, 1, 0.07 if stick_active else 0.04))
	draw_arc(base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
	var knob := base + Vector2(_stick_vec.x, -_stick_vec.y) * STICK_RADIUS
	draw_circle(knob, 34, Color(1, 1, 1, 0.3 if stick_active else 0.15))
	var bs := _buttons()
	for name in bs:
		var b: Dictionary = bs[name]
		var held: bool = (name == "fire" and _fire_held_touch) or _held_buttons.has(name)
		var col := Color(0.78, 0.19, 0.16) if name == "fire" else Color(1, 1, 1)
		if name == "interact" and not interact_ok:
			col = Color(0.6, 0.6, 0.6)
		draw_circle(b.pos, b.r, Color(col.r, col.g, col.b, 0.38 if held else 0.18))
		draw_arc(b.pos, b.r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.7), 2.5, true)
		var fs := 22 if b.r > 40 else 18
		var label: String = b.label
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, b.pos + Vector2(-tw / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))
