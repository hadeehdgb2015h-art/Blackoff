class_name PauseMenu
extends Control
## Pause overlay for solo practice (online play will not pause the zone).

signal resume
signal quit

var _box: VBoxContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	panel.add_child(_box)
	_box.add_child(UiTheme.label("PAUSED", 36, UiTheme.ACCENT))
	_box.add_child(UiTheme.button("Resume", func(): resume.emit()))
	_box.add_child(UiTheme.button("Settings", _open_settings))
	_box.add_child(UiTheme.button("Quit to menu", func(): quit.emit()))


func _open_settings() -> void:
	var s := SettingsPanel.new()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(s)
	s.closed.connect(center.queue_free)
	s.open_layout.connect(func():
		var ed := LayoutEditor.new()
		add_child(ed))
