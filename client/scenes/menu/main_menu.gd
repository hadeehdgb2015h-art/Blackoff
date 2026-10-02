extends Control
## Main menu: a screenshot backdrop, the game title, one big PLAY button,
## solo practice, settings / controls layout / how to play, and the player's
## profile card (name and record when logged in through Telegram).
## ?autostart=1 jumps straight into solo practice (browser smoke test with
## ?bot=1); with ?server=… or ?online=1 it starts quick play online instead.
## ?screen=layout opens the controls editor, ?screen=hunt the weekly hunt (screenshot tests).

const GAME := "res://scenes/game/game.tscn"
const BACKDROP := "res://assets/ui/menu_bg.jpg"

var _profile_name: Label
var _profile_stats: Label
var _profile_hint: Label
var _play: Button
var _play_inf: Button
var _overlay: Control
var _board_button: Button


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_title()
	_build_left_column()
	_build_profile_card()
	_build_footer()
	Audio.play_music("menu")

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
	if Platform.query_param("screen") == "layout":
		_open_layout.call_deferred()
	elif Platform.query_param("screen") == "hunt":
		# screenshot tests: open the weekly hunt once logged in (needs ?server= and ?name=)
		if Net.status in ["offline", "failed"] and Net.is_online_available():
			Net.connect_to_server(false)
		Net.status_changed.connect(func(st: String):
			if st == "ready" and _overlay == null:
				_show_leaderboard())
	if Platform.query_param("autostart") == "1":
		var online := Platform.query_param("server") != "" or Platform.query_param("online") == "1"
		var inf := Platform.query_param("mode") == "infection"
		(_play_infection if online and inf else (_play_online if online else _play_solo)).call_deferred()


# ------------------------------------------------------------------ layout

func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists(BACKDROP):
		var tex := TextureRect.new()
		tex.texture = load(BACKDROP)
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(tex)
	# darken the left side so text stays readable over the picture
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.03, 0.92))
	g.add_point(0.55, Color(0.02, 0.02, 0.03, 0.45))
	g.set_color(g.get_point_count() - 1, Color(0.02, 0.02, 0.03, 0.15))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.ACCENT
	stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_right = 8
	add_child(stripe)


func _build_title() -> void:
	var title := UiTheme.label("BLACKOFF", 84, UiTheme.TEXT)
	title.position = Vector2(80, 36)
	add_child(title)
	var sub := UiTheme.label("DARK FANTASY ZOMBIE SURVIVAL  ·  CO-OP", 20, UiTheme.MUTED)
	sub.position = Vector2(86, 130)
	add_child(sub)


func _build_left_column() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.position = Vector2(84, 190)
	col.custom_minimum_size = Vector2(520, 0)
	add_child(col)
	var mode := HBoxContainer.new()
	mode.add_theme_constant_override("separation", 10)
	var tag := UiTheme.label("ZOMBIES", 20, UiTheme.ACCENT)
	mode.add_child(tag)
	mode.add_child(UiTheme.label("co-op: survive the waves with up to 5 players", 18, UiTheme.MUTED))
	col.add_child(mode)
	_play = UiTheme.big_button("PLAY ONLINE", _play_online)
	col.add_child(_play)
	var mode2 := HBoxContainer.new()
	mode2.add_theme_constant_override("separation", 10)
	mode2.add_child(UiTheme.label("INFECTION", 20, Color(0.45, 0.85, 0.5)))
	mode2.add_child(UiTheme.label("players vs players: soldiers against the infected, up to 10", 18, UiTheme.MUTED))
	col.add_child(mode2)
	_play_inf = UiTheme.big_button("PLAY INFECTION", _play_infection)
	col.add_child(_play_inf)
	var why := ""
	if not Net.is_online_available():
		why = "  (server not set)"
	elif not Platform.is_telegram and Platform.query_param("server") == "" and Platform.query_param("name") == "":
		why = "  (open in Telegram)"
	if why != "":
		for b in [_play, _play_inf]:
			b.disabled = true
			b.text += why
	col.add_child(UiTheme.button("SOLO PRACTICE", _play_solo))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UiTheme.button("SETTINGS", _settings))
	row.add_child(UiTheme.button("CONTROLS", _open_layout))
	row.add_child(UiTheme.button("HOW TO PLAY", _how_to_play))
	col.add_child(row)
	_board_button = UiTheme.button("WEEKLY HUNT  ·  TON leaderboard", _show_leaderboard)
	_board_button.disabled = true
	col.add_child(_board_button)
	var soon := UiTheme.label("Online: voice chat with MIC / SPK on the HUD. Infection kills count for the match, TON comes from zombies only.", 16, UiTheme.MUTED)
	col.add_child(soon)
	if Platform.query_param("debug") == "1":
		col.add_child(UiTheme.button("DIAGNOSTICS", func(): get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")))


func _build_profile_card() -> void:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	card.offset_left = -400
	card.offset_right = -28
	card.offset_top = 28
	card.offset_bottom = 28
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(UiTheme.label("PLAYER", 16, UiTheme.MUTED))
	_profile_name = UiTheme.label("Guest", 28, UiTheme.TEXT)
	v.add_child(_profile_name)
	_profile_stats = UiTheme.label("", 20, UiTheme.GOLD)
	v.add_child(_profile_stats)
	_profile_hint = UiTheme.label("", 16, UiTheme.MUTED)
	_profile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_profile_hint)


func _build_footer() -> void:
	var ver := UiTheme.label("v%s  ·  build %s" % [ProjectSettings.get_setting("application/config/version"),
		Platform.build_id()], 16, UiTheme.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -420
	ver.offset_top = -36
	ver.offset_right = -24
	ver.offset_bottom = -10
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)


# ------------------------------------------------------------------ profile

func _on_net_status(_s: String) -> void:
	_show_profile()


func _on_net_message(msg_name: String, _msg: Dictionary) -> void:
	if msg_name == "profile":
		_show_profile()


func _show_profile() -> void:
	var p := Net.profile
	if p.is_empty() or Net.display_name == "":
		_profile_name.text = "Guest"
		_profile_stats.text = ""
		if Net.status == "connecting" or Net.status == "handshake":
			_profile_hint.text = "Logging in…"
		elif Platform.is_telegram:
			_profile_hint.text = "Your record is saved to your Telegram account."
		else:
			_profile_hint.text = "Open the game from the Telegram bot to play online and keep your record."
		return
	_profile_name.text = Net.display_name
	_profile_stats.text = "Best wave %d  ·  %d kills  ·  %d games" % [p.bestWave, p.kills, p.games]
	var ton := "TON %.3f" % (float(p.tonMicro) / 1000000.0)
	if p.weekRank > 0:
		ton += "   ·   this week #%d with %d kills" % [p.weekRank, p.weekKills]
	_profile_hint.text = ton if Net.ton_per_kill > 0 else "Online and ready."
	_board_button.disabled = false


# ------------------------------------------------------------------ actions

func _play_solo() -> void:
	Net.online_requested = false
	Platform.request_fullscreen()
	get_tree().change_scene_to_file(GAME)


func _play_online() -> void:
	Net.online_requested = true
	Net.mode = 0
	Platform.request_fullscreen()
	get_tree().change_scene_to_file(GAME)


func _play_infection() -> void:
	Net.online_requested = true
	Net.mode = 1
	Platform.request_fullscreen()
	get_tree().change_scene_to_file(GAME)


func _settings() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var s := SettingsPanel.new()
	center.add_child(s)
	s.closed.connect(center.queue_free)
	s.open_layout.connect(_open_layout)


func _open_layout() -> void:
	var ed := LayoutEditor.new()
	add_child(ed)
	print("[menu] controls layout editor opened")


func _show_leaderboard() -> void:
	if _overlay:
		return
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := UiTheme.label("WEEKLY HUNT", 32, UiTheme.ACCENT)
	v.add_child(title)
	var sub := UiTheme.label("Loading…", 18, UiTheme.MUTED)
	v.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var me := UiTheme.label("", 20, UiTheme.GOLD)
	v.add_child(me)
	var note := UiTheme.label("Every zombie you kill online earns TON points. The week's top hunter gets the prize, paid by the game owner.", 15, UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	v.add_child(UiTheme.button("Close", func():
		_overlay.queue_free()
		_overlay = null))
	var fill := func(b: Dictionary) -> void:
		if not is_instance_valid(grid):
			return
		title.text = "WEEKLY HUNT  ·  %s" % str(b.get("week", ""))
		sub.text = str(b.get("prize", "")) if str(b.get("prize", "")) != "" else "Top hunters this week"
		for c in grid.get_children():
			c.queue_free()
		for h in ["#", "PLAYER", "KILLS", "TON"]:
			grid.add_child(UiTheme.label(h, 16, UiTheme.MUTED))
		for e in b.get("entries", []):
			grid.add_child(UiTheme.label(str(int(e.rank)), 20))
			grid.add_child(UiTheme.label(str(e.name), 20))
			grid.add_child(UiTheme.label(str(int(e.kills)), 20))
			grid.add_child(UiTheme.label("%.3f" % (float(e.tonMicro) / 1000000.0), 20))
		if b.get("entries", []).is_empty():
			grid.add_child(UiTheme.label("No kills yet this week. Be the first.", 18))
		if int(b.get("myRank", 0)) > 0:
			me.text = "You: #%d  ·  %d kills  ·  TON %.3f this week" % [int(b.myRank), int(b.myKills), float(b.myTonMicro) / 1000000.0]
		else:
			me.text = "You: no kills yet this week"
	if not Net.leaderboard.is_empty():
		fill.call(Net.leaderboard)
	Net.leaderboard_received.connect(fill, CONNECT_ONE_SHOT)
	Net.request_leaderboard()


func _how_to_play() -> void:
	if _overlay:
		return
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UiTheme.label("HOW TO PLAY", 32, UiTheme.ACCENT))
	for line in [
		"Left thumb: move.  Right thumb: drag to aim, FIRE also aims while held.",
		"Survive the waves. Kills and hits earn credits ($).",
		"Buy weapons and ammo on the walls, or gamble on the SUPPLY CACHE under the green beam.",
		"Perk machines give lasting bonuses (health, reload, speed, swap) until you go down.",
		"Zombies may drop power-ups: INSTA-KILL, DOUBLE POINTS, MAX AMMO, NUKE, FIRE SALE. Walk over them.",
		"A downed teammate bleeds out in 30 s: stand next to them and hold REVIVE.",
		"If everyone is down, the game is over. Your best wave is saved to your Telegram account.",
	]:
		var l := UiTheme.label("•  " + line, 19)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	v.add_child(UiTheme.button("Close", func():
		_overlay.queue_free()
		_overlay = null))
