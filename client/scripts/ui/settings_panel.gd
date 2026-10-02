class_name SettingsPanel
extends PanelContainer
## Settings dialog used by the main menu and the pause menu.

signal closed

var _sens_label: Label
var _vol_label: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	add_child(v)
	v.add_child(UiTheme.label("SETTINGS", 32, UiTheme.ACCENT))

	_sens_label = UiTheme.label("")
	v.add_child(_sens_label)
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = Settings.sensitivity
	sens.custom_minimum_size = Vector2(0, 40)
	sens.value_changed.connect(_on_sens)
	v.add_child(sens)

	_vol_label = UiTheme.label("")
	v.add_child(_vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.master_volume
	vol.custom_minimum_size = Vector2(0, 40)
	vol.value_changed.connect(_on_vol)
	v.add_child(vol)

	v.add_child(UiTheme.label("Graphics quality", 22, UiTheme.MUTED))
	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for name in Settings.QUALITY:
		var b := Button.new()
		b.text = name.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Settings.quality == name
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): Settings.quality = name)
		q.add_child(b)
	v.add_child(q)

	var inv := CheckButton.new()
	inv.text = "Invert vertical look"
	inv.button_pressed = Settings.invert_y
	inv.toggled.connect(func(on): Settings.invert_y = on)
	v.add_child(inv)
	var fps := CheckButton.new()
	fps.text = "Show FPS"
	fps.button_pressed = Settings.show_fps
	fps.toggled.connect(func(on): Settings.show_fps = on)
	v.add_child(fps)

	v.add_child(UiTheme.button("Done", _close))
	_refresh()


func _on_sens(x: float) -> void:
	Settings.sensitivity = x
	_refresh()


func _on_vol(x: float) -> void:
	Settings.master_volume = x
	_refresh()


func _refresh() -> void:
	_sens_label.text = "Look sensitivity: %.2f" % Settings.sensitivity
	_vol_label.text = "Volume: %d%%" % roundi(Settings.master_volume * 100)


func _close() -> void:
	Settings.save()
	closed.emit()
	queue_free()
