class_name PauseMenu
extends Control
## Pause overlay (online play does not pause the zone). Online it also offers
## the squad invite.

signal resume
signal quit
signal invite  ## online: share the squad invite link

var _box: VBoxContainer
var where := "game"  ## for problem reports: the game sets the wave


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
	I18n.dir(_box)
	_box.add_theme_constant_override("separation", 14)
	panel.add_child(_box)
	Platform.on_back(self, func(): resume.emit())
	_box.add_child(UiTheme.label(tr("PAUSED"), 36, UiTheme.ACCENT))
	_box.add_child(UiTheme.button(tr("Resume"), func(): resume.emit()))
	if Social.can_invite():
		_box.add_child(UiTheme.gold_button(tr("Invite friends"), func(): invite.emit()))
	_box.add_child(UiTheme.button(tr("Settings"), _open_settings))
	_box.add_child(UiTheme.button(tr("Report a problem"), _report))
	_box.add_child(UiTheme.button(tr("Quit to menu"), func(): quit.emit()))


func _open_settings() -> void:
	var s := SettingsPanel.new()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(s)
	s.closed.connect(center.queue_free)
	s.report.connect(_report)
	s.open_layout.connect(func():
		var ed := LayoutEditor.new()
		add_child(ed))


## The screenshot is of the game: this menu is hidden while it is taken.
func _report() -> void:
	ReportPanel.open(get_parent(), [self], where)
