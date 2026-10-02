class_name LayoutEditor
extends Control
## Drag the touch controls where you like, resize the selected one, add a
## second FIRE button on the left, set the HUD opacity. Saves to Settings
## (TouchLayout); Reset restores the defaults. Opened from Settings or the menu.

signal closed

var _controls: TouchControls
var _layout: Dictionary
var _selected: String = ""
var _drag_index: int = -1
var _drag_offset := Vector2.ZERO
var _size_slider: HSlider
var _fire2: CheckButton
var _title: Label
var _ring: Ring


## Selection highlight drawn above the controls (a child added after them).
class Ring extends Control:
	var center := Vector2.ZERO
	var radius: float = 0.0

	func _draw() -> void:
		if radius > 0.0:
			draw_arc(center, radius, 0, TAU, 48, Color(1.0, 0.8, 0.3, 0.9), 3.0, true)


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.06, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_controls = TouchControls.new()
	_controls.edit_mode = true
	_controls.interact_label = "USE"
	add_child(_controls)
	_controls.layout = TouchLayout.resolve(Settings.layout, _view_size())
	_layout = _controls.layout
	_controls.opacity = Settings.hud_opacity
	_ring = Ring.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)

	# top bar (leaves the corners free: the pause button lives top-right)
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	bar.offset_left = 100
	bar.offset_right = -110
	bar.offset_top = 8
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.92)
	style.set_content_margin_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_title = UiTheme.title("LAYOUT  ·  drag a button", 16, UiTheme.GOLD)
	_title.custom_minimum_size = Vector2(190, 0)
	row.add_child(_title)
	row.add_child(UiTheme.label("Size", 16, UiTheme.MUTED))
	_size_slider = HSlider.new()
	_size_slider.min_value = TouchLayout.MIN_SCALE
	_size_slider.max_value = TouchLayout.MAX_SCALE
	_size_slider.step = 0.05
	_size_slider.value = 1.0
	_size_slider.custom_minimum_size = Vector2(120, 32)
	_size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size_slider.value_changed.connect(_on_size)
	row.add_child(_size_slider)
	row.add_child(UiTheme.label("Opacity", 16, UiTheme.MUTED))
	var op := HSlider.new()
	op.min_value = 0.3
	op.max_value = 1.0
	op.step = 0.05
	op.value = Settings.hud_opacity
	op.custom_minimum_size = Vector2(100, 32)
	op.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	op.value_changed.connect(func(v: float):
		_controls.opacity = v
		_controls.queue_redraw())
	row.add_child(op)
	_fire2 = CheckButton.new()
	_fire2.text = "Left FIRE"
	_fire2.add_theme_font_size_override("font_size", 18)
	_fire2.button_pressed = bool(_layout.fire2.get("enabled", false))
	_fire2.toggled.connect(func(on: bool):
		_layout.fire2["enabled"] = on
		_controls.queue_redraw())
	row.add_child(_fire2)
	for b in [UiTheme.button("RESET", _reset), UiTheme.gold_button("SAVE", func(): _save(op.value)),
			UiTheme.button("CANCEL", func():
				closed.emit()
				queue_free())]:
		b.add_theme_font_size_override("font_size", 16)
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxTexture = b.get_theme_stylebox(st).duplicate()
			sb.content_margin_left = 14
			sb.content_margin_right = 14
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
			b.add_theme_stylebox_override(st, sb)
		row.add_child(b)
	_select("fire")
	print("[layout] editor ready: %d controls, view %s" % [_controls._buttons().size(), str(_view_size())])


func _view_size() -> Vector2:
	var s := get_viewport_rect().size
	return s if s.x > 0 else Vector2(1280, 720)


func _select(name: String) -> void:
	_selected = name
	_size_slider.set_value_no_signal(TouchLayout.scale(_layout, name))
	_title.text = "LAYOUT · %s" % name.to_upper()
	_update_ring()


func _update_ring() -> void:
	if _selected == "":
		_ring.radius = 0.0
	else:
		_ring.center = TouchLayout.position(_layout, _selected, _view_size())
		var base: float = _controls._stick_radius() if _selected == "stick" else float(_controls.BASE_RADIUS[_selected]) * TouchLayout.scale(_layout, _selected)
		_ring.radius = base + 10.0
	_ring.queue_redraw()


func _on_size(v: float) -> void:
	if _selected != "":
		_layout[_selected]["s"] = v
		_controls.queue_redraw()
		_update_ring()


func _reset() -> void:
	_layout = TouchLayout.defaults(_view_size())
	_controls.layout = _layout
	_fire2.set_pressed_no_signal(false)
	_controls.queue_redraw()
	_select(_selected if _selected != "" else "fire")


func _save(opacity: float) -> void:
	var saved := {}
	for name in TouchLayout.NAMES:
		saved[name] = _layout[name].duplicate()
	Settings.layout = saved
	Settings.hud_opacity = opacity
	Settings.save()
	closed.emit()
	queue_free()


## Control under `p`: a button name, "stick", or "".
func _hit(p: Vector2) -> String:
	var bs: Dictionary = _controls._buttons()
	for name in bs:
		if p.distance_to(bs[name].pos) <= bs[name].r * 1.15:
			return "use" if name in ["interact", "revive"] else name
	if p.distance_to(_controls._stick_home()) <= _controls._stick_radius() * 1.1:
		return "stick"
	return ""


func _gui_input(event: InputEvent) -> void:
	_handle(event)


func _input(event: InputEvent) -> void:
	# touches arrive here (the controls themselves ignore input in edit mode)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle(event)


func _handle(event: InputEvent) -> void:
	var size_v := _view_size()
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		var idx: int = event.index if event is InputEventScreenTouch else 0
		if pressed and _drag_index < 0:
			var hit := _hit(pos)
			if hit != "":
				_drag_index = idx
				_drag_offset = TouchLayout.position(_layout, hit, size_v) - pos
				_select(hit)
		elif not pressed and idx == _drag_index:
			_drag_index = -1
	elif (event is InputEventScreenDrag and event.index == _drag_index) or (event is InputEventMouseMotion and _drag_index == 0 and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if _selected != "":
			TouchLayout.place(_layout, _selected, event.position + _drag_offset, size_v)
			_controls.queue_redraw()
			_update_ring()
