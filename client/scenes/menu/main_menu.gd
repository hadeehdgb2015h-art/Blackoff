extends Control
## Main menu. ?autostart=1 jumps straight into solo practice (used by the
## automated browser smoke test together with ?bot=1).

const GAME := "res://scenes/game/game.tscn"


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.ACCENT
	stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_right = 10
	add_child(stripe)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 90
	col.offset_top = -230
	col.offset_bottom = 230
	col.offset_right = 600
	add_child(col)
	col.add_child(UiTheme.label("BLACKOFF", 84, UiTheme.ACCENT))
	col.add_child(UiTheme.label("Facility 01  ·  co-op survival", 22, UiTheme.MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	col.add_child(spacer)
	col.add_child(UiTheme.button("SOLO PRACTICE", _play))
	var quick := UiTheme.button("QUICK PLAY  ONLINE", _play_online)
	quick.disabled = not Net.is_online_available()
	if quick.disabled:
		quick.text = "QUICK PLAY  (server not set)"
	col.add_child(quick)
	col.add_child(UiTheme.button("SETTINGS", _settings))
	col.add_child(UiTheme.button("DIAGNOSTICS", func(): get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")))

	var ver := UiTheme.label("v%s  ·  build %s" % [ProjectSettings.get_setting("application/config/version"),
		Platform.build_id()], 18, UiTheme.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -420
	ver.offset_top = -40
	ver.offset_right = -24
	ver.offset_bottom = -12
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)

	if not SharedData.is_valid():
		var err := UiTheme.label("Data error: " + "; ".join(SharedData.errors), 18, UiTheme.ACCENT)
		err.position = Vector2(90, 20)
		add_child(err)
	if Platform.query_param("autostart") == "1":
		(_play_online if Platform.query_param("server") != "" else _play).call_deferred()


func _play() -> void:
	Net.online_requested = false
	Platform.request_fullscreen()
	get_tree().change_scene_to_file(GAME)


func _play_online() -> void:
	Net.online_requested = true
	Platform.request_fullscreen()
	get_tree().change_scene_to_file(GAME)


func _settings() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var s := SettingsPanel.new()
	center.add_child(s)
	s.closed.connect(center.queue_free)
