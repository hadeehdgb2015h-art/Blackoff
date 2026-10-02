extends Control
## Main menu. ?autostart=1 jumps straight into solo practice (used by the
## automated browser smoke test together with ?bot=1); with ?server=… or
## ?online=1 it starts quick play online instead.

const GAME := "res://scenes/game/game.tscn"

var _profile_label: Label


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
	_profile_label = UiTheme.label("", 20, UiTheme.ACCENT)
	col.add_child(_profile_label)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	col.add_child(spacer)
	col.add_child(UiTheme.button("SOLO PRACTICE", _play))
	var quick := UiTheme.button("QUICK PLAY  ONLINE", _play_online)
	quick.disabled = not Net.is_online_available()
	if quick.disabled:
		quick.text = "QUICK PLAY  (server not set)"
	elif not Platform.is_telegram and Platform.query_param("server") == "" and Platform.query_param("name") == "":
		# the live server only accepts Telegram logins
		quick.disabled = true
		quick.text = "QUICK PLAY  (open in Telegram)"
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
	# Inside Telegram: log in right away so the player's stats show here and
	# quick play starts faster. Listening also keeps Net from buffering.
	Net.status_changed.connect(_on_net_status)
	Net.message.connect(_on_net_message)
	if Net.is_online_available() and Platform.is_telegram and Net.status in ["offline", "failed"]:
		Net.connect_to_server(false)
	_show_profile()
	if Platform.query_param("autostart") == "1":
		var online := Platform.query_param("server") != "" or Platform.query_param("online") == "1"
		(_play_online if online else _play).call_deferred()


func _on_net_status(_s: String) -> void:
	_show_profile()


func _on_net_message(msg_name: String, _msg: Dictionary) -> void:
	if msg_name == "profile":
		_show_profile()


func _show_profile() -> void:
	var p := Net.profile
	if p.is_empty() or Net.display_name == "":
		_profile_label.text = ""
		return
	_profile_label.text = "%s  ·  best wave %d  ·  %d kills  ·  %d games" % [Net.display_name, p.bestWave, p.kills, p.games]


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
