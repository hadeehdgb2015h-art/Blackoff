class_name TouchControls
extends Control
## Multi-touch controls (floating move stick, drag-to-aim anywhere on the
## right side, fire button that also aims while held, reload, switch,
## contextual interact/revive, pause) plus keyboard/mouse for desktop.
## Produces one PlayerIntent per sim tick via sample().

signal pause_requested
signal voice_toggled(which: String)   ## "mic" or "speaker" tapped

const AIM_DEG_PER_PX := 0.16     ## touch look at sensitivity 1.0 (view is 720 px tall)
const AIM_PITCH_SCALE := 0.8     ## vertical look is a bit slower than horizontal
const AIM_SMOOTH_RATE := 40.0    ## 1/s; removes finger jitter (~25 ms of smoothing)
const MOUSE_GUARD_MS := 1500     ## ignore browser mouse events this long after a real touch
const STICK_RADIUS := 85.0
const PITCH_LIMIT := 1.35

enum Role { NONE, STICK, AIM, FIRE, BUTTON }

var yaw: float = 0.0
var pitch: float = 0.0
var interact_label: String = ""   ## set by the game; empty hides the button
var interact_ok: bool = true
var revive_available: bool = false
var enabled: bool = true
var aim_friction: float = 1.0     ## set by the game each frame: < 1 slows the look over a target
var edit_mode: bool = false       ## layout editor: draw every control, take no input
var layout: Dictionary = {}       ## TouchLayout (resolved on first use)
var opacity: float = 1.0
var voice_buttons: bool = false   ## show MIC and SPK (online with voice chat)
var melee_mode: bool = false      ## infection, playing infected: FIRE is ATTACK, no reload/switch
var mic_on: bool = false
var speaker_on: bool = true
var mic_talking: bool = false     ## pulse the mic ring while the player speaks
var mic_blocked: bool = false     ## permission denied / unsupported: drawn crossed and grey

var _touches := {}  ## index -> {role, button, start, last}
var _drawn_state: Array = []
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _fire_held_touch: bool = false
var _latched: int = 0
var _held_buttons := {}  ## button name -> true while a touch holds it
var _seq: int = 0
var _keys_move := Vector2.ZERO
var _mouse_fire: bool = false
var _font: Font
var _aim_pending := Vector2.ZERO  ## touch look not yet applied (smoothing)
var _last_touch_ms: int = -100000


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	reload_layout()
	Settings.changed.connect(reload_layout)


func reload_layout() -> void:
	layout = TouchLayout.resolve(Settings.layout, size if size.x > 0 else Vector2(1280, 720))
	opacity = Settings.hud_opacity
	queue_redraw()


func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = p


## Queues a one-tick button press (used by scripted showcases and tutorials).
func queue_press(bit: int) -> void:
	_latched |= bit


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
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_F):
		b |= PlayerIntent.REVIVE  # keyboard: hold E (or F) next to a downed teammate
	it.buttons = b
	_latched = 0
	return it


# ------------------------------------------------------------ layout

const BASE_RADIUS := {"fire": 78.0, "fire2": 64.0, "reload": 44.0, "switch": 44.0, "use": 52.0, "pause": 30.0, "mic": 28.0, "speaker": 28.0}


func _buttons() -> Dictionary:
	if layout.is_empty():
		reload_layout()
	var s := size
	var d := {}
	var at := func(name: String) -> Vector2: return TouchLayout.position(layout, name, s)
	var rad := func(name: String) -> float: return BASE_RADIUS[name] * TouchLayout.scale(layout, name)
	var fire_label := "ATTACK" if melee_mode else "FIRE"
	d["fire"] = {"pos": at.call("fire"), "r": rad.call("fire"), "label": fire_label}
	if layout.fire2.get("enabled", false) or edit_mode:
		d["fire2"] = {"pos": at.call("fire2"), "r": rad.call("fire2"), "label": fire_label}
	if not melee_mode or edit_mode:
		d["reload"] = {"pos": at.call("reload"), "r": rad.call("reload"), "label": "R"}
		d["switch"] = {"pos": at.call("switch"), "r": rad.call("switch"), "label": "SWAP"}
	d["pause"] = {"pos": at.call("pause"), "r": rad.call("pause"), "label": "II"}
	if voice_buttons or edit_mode:
		d["mic"] = {"pos": at.call("mic"), "r": rad.call("mic"), "label": "MIC"}
		d["speaker"] = {"pos": at.call("speaker"), "r": rad.call("speaker"), "label": "SPK"}
	if revive_available:
		d["revive"] = {"pos": at.call("use"), "r": rad.call("use"), "label": "REVIVE"}
	elif interact_label != "" or edit_mode:
		d["interact"] = {"pos": at.call("use"), "r": rad.call("use"), "label": "USE"}
	return d


func _stick_home() -> Vector2:
	if layout.is_empty():
		reload_layout()
	return TouchLayout.position(layout, "stick", size)


func _stick_radius() -> float:
	return STICK_RADIUS * (TouchLayout.scale(layout, "stick") if not layout.is_empty() else 1.0)


# ------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if edit_mode:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and _touch_recent():
		return  # compatibility mouse events a phone browser sends after a tap
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
			_aim(event.relative * 0.75)
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


func _touch_recent() -> bool:
	# Real (not mouse-emulated) touches only, so desktop mouse play is unaffected.
	return Time.get_ticks_msec() - _last_touch_ms < MOUSE_GUARD_MS


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.device != InputEvent.DEVICE_ID_EMULATION:
		_last_touch_ms = Time.get_ticks_msec()
	if e.pressed:
		if not enabled:
			return
		var hit := _hit_button(e.position)
		if hit != "":
			_touches[e.index] = {"role": Role.FIRE if hit.begins_with("fire") else Role.BUTTON, "button": hit, "last": e.position, "t": Time.get_ticks_usec()}
			_press(hit)
		elif e.position.x < size.x * 0.42:
			_touches[e.index] = {"role": Role.STICK, "last": e.position, "t": Time.get_ticks_usec()}
			_stick_origin = e.position
			_stick_vec = Vector2.ZERO
		else:
			_touches[e.index] = {"role": Role.AIM, "last": e.position, "t": Time.get_ticks_usec()}
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
	if e.device != InputEvent.DEVICE_ID_EMULATION:
		_last_touch_ms = Time.get_ticks_msec()
	if not _touches.has(e.index):
		return
	var t: Dictionary = _touches[e.index]
	var delta: Vector2 = e.position - t.last
	var now := Time.get_ticks_usec()
	var dt := maxf(float(now - int(t.t)) / 1e6, 0.004)
	t.last = e.position
	t.t = now
	match t.role:
		Role.STICK:
			var off := e.position - _stick_origin
			var sr := _stick_radius()
			if off.length() > sr * 1.6:
				_stick_origin = e.position - off.normalized() * sr * 1.6
				off = e.position - _stick_origin
			var v := off / sr
			_stick_vec = Vector2(v.x, -v.y).limit_length(1.0)
		Role.AIM, Role.FIRE:
			# Response curve: slow drags are precise, fast swipes turn quickly.
			var speed := delta.length() / dt
			_aim_pending += delta * lerpf(0.6, 1.2, smoothstep(120.0, 1400.0, speed))
	get_viewport().set_input_as_handled()
	queue_redraw()


func _aim(delta_px: Vector2) -> void:
	var k := deg_to_rad(AIM_DEG_PER_PX) * Settings.sensitivity * aim_friction
	yaw = wrapf(yaw - delta_px.x * k, -PI, PI)
	var dy := delta_px.y * k * AIM_PITCH_SCALE * (-1.0 if Settings.invert_y else 1.0)
	pitch = clampf(pitch - dy, -PITCH_LIMIT, PITCH_LIMIT)


func _press(name: String) -> void:
	match name:
		"fire", "fire2":
			_fire_held_touch = true
			_latched |= PlayerIntent.FIRE_PRESSED
		"pause":
			pause_requested.emit()
		"mic", "speaker":
			voice_toggled.emit(name)
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
	_aim_pending = Vector2.ZERO
	_mouse_fire = false
	_keys_move = Vector2.ZERO
	queue_redraw()


# ------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	if _aim_pending != Vector2.ZERO:
		var step := _aim_pending * (1.0 - exp(-AIM_SMOOTH_RATE * delta))
		if _aim_pending.length() < 0.05:
			step = _aim_pending
		_aim_pending -= step
		_aim(step)
	# Redrawing every frame costs real battery on phones: only when the drawn
	# state changed (touch events already request a redraw themselves).
	var state := [interact_label, interact_ok, revive_available, enabled, edit_mode, voice_buttons, mic_on, speaker_on,
		mic_blocked, melee_mode, opacity, size]
	if state != _drawn_state or (mic_talking and mic_on):
		_drawn_state = state
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var stick_active := false
	for t in _touches.values():
		stick_active = stick_active or t.role == Role.STICK
	var base := _stick_origin if stick_active else _stick_home()
	var sr := _stick_radius()
	var op := opacity
	draw_circle(base, sr, Color(1, 1, 1, (0.07 if stick_active else 0.04) * op))
	draw_arc(base, sr, 0, TAU, 48, Color(1, 1, 1, 0.25 * op), 2.0, true)
	var knob := base + Vector2(_stick_vec.x, -_stick_vec.y) * sr
	draw_circle(knob, 34 * sr / STICK_RADIUS, Color(1, 1, 1, (0.3 if stick_active else 0.15) * op))
	var bs := _buttons()
	for name in bs:
		var b: Dictionary = bs[name]
		var held: bool = (name.begins_with("fire") and _fire_held_touch) or _held_buttons.has(name)
		var col := Color(0.78, 0.19, 0.16) if name.begins_with("fire") else Color(1, 1, 1)
		if name == "interact" and not interact_ok:
			col = Color(0.6, 0.6, 0.6)
		var voice_on: bool = (name == "mic" and mic_on) or (name == "speaker" and speaker_on)
		if name in ["mic", "speaker"]:
			col = Color(0.45, 0.85, 0.5) if voice_on else Color(0.75, 0.75, 0.75)
			if name == "mic" and mic_blocked:
				col = Color(0.55, 0.55, 0.55)
			held = held or voice_on
		draw_circle(b.pos, b.r, Color(col.r, col.g, col.b, (0.38 if held else 0.18) * op))
		draw_arc(b.pos, b.r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.7 * op), 2.5, true)
		if name in ["mic", "speaker"]:
			if not voice_on or (name == "mic" and mic_blocked):
				# a slash: muted
				var d: Vector2 = Vector2(1, -1).normalized() * float(b.r) * 0.72
				draw_line(b.pos - d, b.pos + d, Color(0, 0, 0, 0.5 * op), 5.0, true)
				draw_line(b.pos - d, b.pos + d, Color(1, 0.35, 0.3, 0.9 * op), 2.5, true)
			elif name == "mic" and mic_talking:
				var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 90.0)
				draw_arc(b.pos, b.r * pulse + 4.0, 0, TAU, 48, Color(0.45, 0.85, 0.5, 0.8 * op), 2.0, true)
		var fs := 22 if b.r > 40 else 18
		var label: String = b.label
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, b.pos + Vector2(-tw / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85 * op))
