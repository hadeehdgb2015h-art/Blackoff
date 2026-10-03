class_name KeypadPanel
extends Control
## A digit keypad for a puzzle object (phase 31): the terminal's code, the
## transmitter's frequency. The game keeps running behind it (online); the
## server checks the code.

signal submitted(code: String)
signal closed

var length := 4
var title := ""
var _code := ""
var _display: Label
var _enter: Button


func setup(code_length: int, title_text: String) -> KeypadPanel:
	length = clampi(code_length, 1, 8)
	title = title_text
	return self


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(18))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	I18n.dir(v)
	v.add_child(UiTheme.title(title, 24, UiTheme.GOLD))
	_display = UiTheme.label("", 40, UiTheme.TEXT)
	_display.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.add_theme_font_override("font", UiTheme.display_font())
	v.add_child(_display)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.layout_direction = Control.LAYOUT_DIRECTION_LTR  # a keypad reads 1 2 3 in every language
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "<"]:
		var b := UiTheme.button(key, _press.bind(key))
		b.custom_minimum_size = Vector2(96, 58)
		b.add_theme_font_size_override("font_size", 26)
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	I18n.dir(row)
	_enter = UiTheme.gold_button(tr("ENTER"), _on_enter)
	row.add_child(_enter)
	row.add_child(UiTheme.button(tr("CLOSE"), _close))
	Platform.on_back(self, _close)
	_refresh()


func _press(key: String) -> void:
	Platform.haptic("light")
	match key:
		"<":
			_code = _code.left(maxi(0, _code.length() - 1))
		"C":
			_code = ""
		_:
			if _code.length() < length:
				_code += key
	_refresh()


func _refresh() -> void:
	var shown := PackedStringArray()
	for i in length:
		shown.append(_code[i] if i < _code.length() else "_")
	_display.text = " ".join(shown)
	_enter.disabled = _code.length() != length


func _on_enter() -> void:
	if _code.length() != length:
		return
	submitted.emit(_code)
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
