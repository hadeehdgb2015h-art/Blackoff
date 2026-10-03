extends Control
## Main menu: a screenshot backdrop, the game title, one big PLAY button,
## solo practice, settings / controls layout / how to play, and the player's
## profile card (name and record when logged in through Telegram).
## ?autostart=1 jumps straight into solo practice (browser smoke test with
## ?bot=1); with ?server=… or ?online=1 it starts quick play online instead.
## ?screen=layout|settings|howto|hunt|daily|profile opens that screen at once (screenshot tests).
## Opened from a friend's invite (t.me/<bot>?startapp=sq<code>, or ?startapp= in
## a browser with ?server=) it goes straight into that friend's game.

const GAME := "res://scenes/game/game.tscn"
const MAP_PATH := "res://scenes/maps/facility_01.tscn"
const BACKDROP := "res://assets/ui/menu_bg.jpg"

var _profile_name: Label
var _profile_stats: Label
var _profile_hint: Label
var _play: Button
var _play_inf: Button
var _overlay: Control
var _board_button: Button
var _invite: Button
var _daily_btn: Button
var _rank_row: Control
var _rank_badge: RankBadge
var _rank_label: Label
var _xp_bar: XpBar
var _daily_dot: Control
var _toast: Label
static var _daily_opened := false   ## the daily panel opens by itself once per session when a reward waits
static var _invite_checked := false  ## the launch link's invite is honoured once per session
var _content: Control   ## everything but the backdrop, inset from the host's buttons (Telegram)


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	# Telegram draws its close/menu buttons over the page: keep the menu clear of them
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ins := Platform.safe_insets(get_viewport_rect().size)
	_content.offset_left = float(ins.left)
	_content.offset_top = float(ins.top)
	_content.offset_right = -float(ins.right)
	_content.offset_bottom = -float(ins.bottom)
	add_child(_content)
	_build_title()
	_build_left_column()
	_build_profile_card()
	_build_footer()
	Audio.play_music("menu")

	if not SharedData.is_valid():
		var err := UiTheme.label(tr("Data error: %s") % "; ".join(SharedData.errors), 18, UiTheme.ACCENT)
		err.position = Vector2(90, 20)
		_content.add_child(err)
	# Inside Telegram: log in right away so the player's stats show here and
	# quick play starts faster. Listening also keeps Net from buffering.
	Net.status_changed.connect(_on_net_status)
	Net.message.connect(_on_net_message)
	Net.daily_received.connect(_on_daily)
	Net.level_up.connect(_on_level_up)
	if Net.is_online_available() and Platform.is_telegram and Net.status in ["offline", "failed"]:
		Net.connect_to_server(false)
	_show_profile()
	if Platform.query_param("screen") == "layout":
		_open_layout.call_deferred()
	elif Platform.query_param("screen") == "settings":
		_settings.call_deferred()
	elif Platform.query_param("screen") == "howto":
		_how_to_play.call_deferred()
	elif Platform.query_param("screen") == "profile":
		# screenshot tests: log in (needs ?server= and ?name=) and show the profile card
		if Net.status in ["offline", "failed"] and Net.is_online_available():
			Net.connect_to_server(false)
	elif Platform.query_param("screen") == "daily":
		# screenshot tests: open the daily panel once logged in (needs ?server= and ?name=)
		_daily_opened = true
		if Net.status in ["offline", "failed"] and Net.is_online_available():
			Net.connect_to_server(false)
		Net.status_changed.connect(func(st: String):
			if st == "ready" and _overlay == null:
				_show_daily())
	elif Platform.query_param("screen") == "hunt":
		# screenshot tests: open the weekly hunt once logged in (needs ?server= and ?name=)
		if Net.status in ["offline", "failed"] and Net.is_online_available():
			Net.connect_to_server(false)
		Net.status_changed.connect(func(st: String):
			if st == "ready" and _overlay == null:
				_show_leaderboard())
	# Once per session, under a curtain: place the map's props, merge its meshes
	# and load the models a match needs, so PLAY (and play again) start at once.
	if not MapCache.is_ready(MAP_PATH):
		var cover := _loading("BLACKOFF")
		await get_tree().process_frame
		await get_tree().process_frame
		MapCache.prepare(MAP_PATH)
		_prewarm()
		cover.queue_free()
	# opened from a friend's invite link: straight into their game, once per session
	if not _invite_checked and Net.take_launch_invite():
		_invite_checked = true
		if Net.is_online_available() and (Platform.is_telegram or Platform.query_param("server") != ""):
			Net.online_requested = true
			Platform.request_fullscreen()
			_enter(tr("JOINING YOUR FRIEND"))
			return
	_invite_checked = true
	if Platform.query_param("autostart") == "1":
		var online := Platform.query_param("server") != "" or Platform.query_param("online") == "1"
		var inf := Platform.query_param("mode") == "infection"
		(_play_infection if online and inf else (_play_online if online else _play_solo)).call_deferred()


# ------------------------------------------------------------------ layout

func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists(BACKDROP):
		var tex := TextureRect.new()
		tex.texture = load(BACKDROP)
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.modulate = Color(0.8, 0.78, 0.8)
		add_child(tex)
	# the left half fades to black so the menu reads over the picture
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.03, 0.96))
	g.add_point(0.5, Color(0.02, 0.02, 0.03, 0.55))
	g.set_color(g.get_point_count() - 1, Color(0.02, 0.02, 0.03, 0.1))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	add_child(UiTheme.vignette(0.9))
	var embers := UiTheme.embers(30)  # 30 soft dots: cheap even on low phones
	embers.position = Vector2(640, 760)
	add_child(embers)
	# a brass hairline frames the screen
	var frame := UiTheme.Rule.new()
	frame.color = UiTheme.BRASS_DARK
	frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	frame.offset_top = -56
	frame.offset_bottom = -42
	frame.offset_left = 60
	frame.offset_right = -60
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)


func _build_title() -> void:
	var glow := UiTheme.title("BLACKOFF", 88, Color(0.6, 0.12, 0.08, 0.55))
	glow.position = Vector2(82, 32)
	glow.add_theme_constant_override("outline_size", 14)
	glow.add_theme_color_override("font_outline_color", Color(0.5, 0.1, 0.06, 0.25))
	_content.add_child(glow)
	var title := UiTheme.title("BLACKOFF", 88, UiTheme.TEXT)
	title.position = Vector2(80, 30)
	title.add_theme_constant_override("outline_size", 6)
	_content.add_child(title)
	var sub := UiTheme.title(UiTheme.spaced(tr("dark fantasy zombie survival")), 15, UiTheme.GOLD)
	sub.position = Vector2(86, 128)
	if I18n.rtl:
		# Arabic is not letter-spaced: a little larger, under the logo's right end
		sub.add_theme_font_size_override("font_size", 17)
		sub.custom_minimum_size = Vector2(516, 0)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sub.position = Vector2(86, 134)
	_content.add_child(sub)
	var r := UiTheme.rule(520)
	r.position = Vector2(84, 154)
	_content.add_child(r)


func _build_left_column() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.position = Vector2(84, 184)
	col.custom_minimum_size = Vector2(520, 0)
	_content.add_child(col)
	_play = UiTheme.big_button(tr("PLAY ONLINE  ·  ZOMBIES"), _play_online)
	col.add_child(_play)
	col.add_child(_caption(tr("Co-op survival: hold the waves with up to 5 players")))
	_play_inf = UiTheme.big_button(tr("PLAY INFECTION"), _play_infection)
	col.add_child(_play_inf)
	col.add_child(_caption(tr("Players vs players: soldiers against the infected, up to 10")))
	var why := ""  # a template around the button's caption
	if not Net.is_online_available():
		why = tr("%s  (server not set)")
	elif not Platform.is_telegram and Platform.query_param("server") == "" and Platform.query_param("name") == "":
		why = tr("%s  (open in Telegram)")
	if why != "":
		for b in [_play, _play_inf]:
			b.disabled = true
			b.text = why % b.text
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.button(tr("SOLO PRACTICE"), _play_solo))
	row.add_child(UiTheme.button(tr("SETTINGS"), _settings))
	row.add_child(UiTheme.button(tr("CONTROLS"), _open_layout))
	col.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_board_button = UiTheme.gold_button(tr("WEEKLY HUNT  ·  TON"), _show_leaderboard)
	_board_button.disabled = true
	row2.add_child(_board_button)
	row2.add_child(UiTheme.button(tr("HOW TO PLAY"), _how_to_play))
	col.add_child(row2)
	if Platform.query_param("debug") == "1":
		col.add_child(UiTheme.button(tr("DIAGNOSTICS"), func(): get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")))
	# right-to-left in Arabic: the column's rows and captions, not the column
	# itself (an absolutely placed Control would be mirrored to the other side)
	for c in col.get_children():
		I18n.dir(c as Control)


func _caption(text: String) -> Label:
	var l := UiTheme.label(text, 15, UiTheme.MUTED)
	l.add_theme_constant_override("outline_size", 3)
	return l


func _build_profile_card() -> void:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	card.offset_left = -392
	card.offset_right = -36
	card.offset_top = 36
	card.offset_bottom = 36
	card.add_theme_stylebox_override("panel", UiTheme.panel_box(18))
	_content.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	I18n.dir(v)
	v.add_child(UiTheme.title(UiTheme.spaced(tr("player")), 12, UiTheme.GOLD))
	_profile_name = UiTheme.title(tr("Guest"), 26, UiTheme.TEXT)
	v.add_child(_profile_name)
	# rank and level (phase 26)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 10)
	I18n.dir(rr)
	_rank_badge = RankBadge.new({}, 46.0)
	rr.add_child(_rank_badge)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_label = UiTheme.label("", 17, UiTheme.TEXT)
	rv.add_child(_rank_label)
	_xp_bar = XpBar.new()
	rv.add_child(_xp_bar)
	rr.add_child(rv)
	_rank_row = rr
	_rank_row.visible = false
	v.add_child(rr)
	v.add_child(UiTheme.rule(300, UiTheme.BRASS_DARK))
	_profile_stats = UiTheme.label("", 18, UiTheme.GOLD)
	v.add_child(_profile_stats)
	_profile_hint = UiTheme.label("", 15, UiTheme.MUTED)
	_profile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_profile_hint)
	_invite = UiTheme.gold_button(tr("INVITE FRIENDS"), func():
		var note := Social.invite()
		if note != "":
			_profile_hint.text = note)
	_invite.visible = false
	v.add_child(_invite)
	_daily_btn = UiTheme.gold_button(tr("DAILY REWARD  ·  MISSIONS"), _show_daily)
	_daily_btn.visible = false
	v.add_child(_daily_btn)
	# a pulsing ember dot on the button while today's reward waits
	_daily_dot = Badge.new()
	_daily_dot.visible = false
	_daily_btn.add_child(_daily_dot)


func _build_footer() -> void:
	var ver := UiTheme.label("v%s  ·  build %s" % [ProjectSettings.get_setting("application/config/version"),
		Platform.build_id()], 13, UiTheme.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -420
	ver.offset_top = -34
	ver.offset_right = -64
	ver.offset_bottom = -12
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_content.add_child(ver)


## A dark curtain with a line of text while the game scene loads (the map is
## batched on entry, which takes a moment on phones).
func _loading(text: String) -> Control:
	var cover := ColorRect.new()
	cover.color = Color(0.02, 0.02, 0.03, 0.82)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	cover.add_child(box)
	var l := UiTheme.title(text, 30, UiTheme.GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var r := UiTheme.rule(360)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(r)
	var hint := UiTheme.label(tr("LOADING THE FACILITY  ·  once per session"), 15, UiTheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	# the title breathes so nobody takes the curtain for a frozen screen
	var tw := l.create_tween().set_loops()  # bound to the label: dies with the curtain
	tw.tween_property(l, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(l, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	return cover


# ------------------------------------------------------------------ profile

func _on_net_status(_s: String) -> void:
	_show_profile()


func _on_net_message(msg_name: String, _msg: Dictionary) -> void:
	if msg_name == "profile":
		_show_profile()


func _show_profile() -> void:
	var p := Net.profile
	if p.is_empty() or Net.display_name == "":
		_profile_name.text = tr("Guest")
		_profile_stats.text = ""
		if Net.status == "connecting" or Net.status == "handshake":
			_profile_hint.text = tr("Logging in…")
		elif Platform.is_telegram:
			_profile_hint.text = tr("Your record is saved to your Telegram account.")
		else:
			_profile_hint.text = tr("Open the game from the Telegram bot to play online and keep your record.")
		return
	_profile_name.text = Net.display_name
	_profile_stats.text = tr("Best wave %d  ·  %d kills  ·  %d games") % [p.bestWave, p.kills, p.games]
	var ton := tr("TON %s") % UiTheme.ton_text(int(p.tonMicro))
	if p.weekRank > 0:
		if int(p.weekKills) == 1:
			ton = tr("TON %s   ·   this week #%d with %d kill") % [UiTheme.ton_text(int(p.tonMicro)), p.weekRank, p.weekKills]
		else:
			ton = tr("TON %s   ·   this week #%d with %d kills") % [UiTheme.ton_text(int(p.tonMicro)), p.weekRank, p.weekKills]
	_profile_hint.text = ton if Net.ton_per_kill > 0 else tr("Online and ready.")
	_board_button.disabled = false
	_invite.visible = Social.can_invite()
	_daily_btn.visible = true
	_update_daily_badge()
	_show_rank(int(p.get("xp", 0)), int(p.get("level", 1)))


func _show_rank(xp: int, level: int) -> void:
	var rank := Progression.rank_for(level)
	_rank_badge.set_rank(rank)
	_rank_label.text = tr("%s  ·  Level %d") % [Progression.rank_name(str(rank.id)), level]
	var lo := Progression.xp_to_reach(level)
	var hi := Progression.xp_to_reach(level + 1)
	if level >= int(Progression.defs().maxLevel):
		_xp_bar.set_values(1, 1, tr("MAX LEVEL"))
	else:
		_xp_bar.set_values(xp - lo, hi - lo, tr("%d / %d XP") % [xp - lo, hi - lo])
	_rank_row.visible = true


## A game raised the level: a banner with the insignia (and the new rank).
func _on_level_up(from_level: int, to_level: int) -> void:
	_show_profile()
	var new_rank := Progression.rank_for(to_level)
	var ranked_up := str(new_rank.id) != str(Progression.rank_for(from_level).id)
	var cover := Control.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.panel_box(28))
	frame.custom_minimum_size = Vector2(460, 0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	frame.add_child(box)
	var badge := RankBadge.new(new_rank, 132.0)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(badge)
	var t := UiTheme.title(tr("NEW RANK") if ranked_up else tr("LEVEL UP"), 44, UiTheme.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sub := UiTheme.title(tr("%s  ·  Level %d") % [Progression.rank_name(str(new_rank.id)), to_level], 24, UiTheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	Audio.ui_sound("powerup", -4.0)
	Platform.haptic("heavy")
	badge.pivot_offset = Vector2(66, 66)
	badge.scale = Vector2(0.4, 0.4)
	var tw := cover.create_tween()
	tw.tween_property(badge, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.2)
	tw.tween_property(cover, "modulate:a", 0.0, 0.6)
	tw.tween_callback(cover.queue_free)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed or e is InputEventScreenTouch and e.pressed:
			cover.queue_free())
	print("[menu] level up %d -> %d" % [from_level, to_level])


# ------------------------------------------------------------------ daily (phase 23)

func _on_daily(d: Dictionary) -> void:
	_update_daily_badge()
	if int(d.get("paidMicro", 0)) > 0 and int(d.get("paidKind", 0)) == 2:
		_show_toast(tr("DAILY MISSIONS  ·  +%s TON") % UiTheme.ton_text(int(d.paidMicro)))
		Audio.ui_sound("powerup", -8.0)
	# once per session, a waiting reward opens the panel by itself
	if not _daily_opened and bool(d.get("canClaim", false)) and _overlay == null and is_inside_tree():
		_daily_opened = true
		_show_daily()


func _update_daily_badge() -> void:
	if _daily_dot:
		_daily_dot.visible = bool(Net.daily.get("canClaim", false))


func _show_daily() -> void:
	if _overlay:
		return
	_daily_opened = true
	var panel := DailyPanel.new()
	_overlay = panel
	panel.closed.connect(func(): _overlay = null)
	_content.add_child(panel)


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _show_toast(text: String) -> void:
	if _toast == null:
		_toast = UiTheme.title("", 24, UiTheme.GOLD)
		_toast.add_theme_constant_override("outline_size", 6)
		_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast.offset_top = 120
		add_child(_toast)
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)


## The ember dot on DAILY REWARD while a reward waits.
class Badge extends Control:
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(16, 16)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		var parent := get_parent() as Control
		if parent:
			position = Vector2(parent.size.x - 12.0, -4.0)
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		draw_circle(Vector2(8, 8), 9.0 + 2.0 * pulse, Color(0.9, 0.3, 0.1, 0.25 + 0.2 * pulse))
		draw_circle(Vector2(8, 8), 7.0, UiTheme.ACCENT)
		draw_circle(Vector2(8, 8), 7.0, UiTheme.GOLD, false, 1.5, true)


# ------------------------------------------------------------------ actions

func _play_solo() -> void:
	Net.online_requested = false
	Platform.request_fullscreen()
	_enter(tr("SOLO PRACTICE"))


## Shows the loading curtain, then changes scene after it has been drawn.
func _enter(label: String) -> void:
	_loading(label)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME)


## Loads the models the match will need while the curtain is up, so the first
## zombie or weapon does not stall the first seconds of play.
func _prewarm() -> void:
	var vis := Visuals.data()
	var paths: Array[String] = []
	for z in vis.get("zombies", {}).values():
		paths.append(str(z.get("model", "")))
	for wid in ["pistol", "rifle"]:
		paths.append(str(vis.get("weapons", {}).get(wid, {}).get("model", "")))
	paths.append(str(vis.get("players", {}).get("soldier", {}).get("model", "")))
	var t0 := Time.get_ticks_msec()
	var n := 0
	for path in paths:
		if path != "" and ResourceLoader.exists(path):
			load(path)
			n += 1
	print("[menu] prewarmed %d models in %d ms" % [n, Time.get_ticks_msec() - t0])


func _play_online() -> void:
	Net.online_requested = true
	Net.mode = 0
	Platform.request_fullscreen()
	_enter(tr("ENTERING THE FACILITY"))


func _play_infection() -> void:
	Net.online_requested = true
	Net.mode = 1
	Platform.request_fullscreen()
	_enter(tr("INFECTION"))


func _settings() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(center)
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
	_content.add_child(_overlay)
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
	I18n.dir(v)
	var title := UiTheme.title(tr("WEEKLY HUNT"), 30, UiTheme.GOLD)
	v.add_child(title)
	v.add_child(UiTheme.rule(620))
	var sub := UiTheme.label(tr("Loading…"), 18, UiTheme.MUTED)
	v.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var me := UiTheme.label("", 20, UiTheme.GOLD)
	v.add_child(me)
	var note := UiTheme.label(tr("Every zombie you kill online earns TON points. The week's top hunter gets the prize, paid by the game owner."), 15, UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	v.add_child(UiTheme.gold_button(tr("CLOSE"), _close_overlay))
	Platform.on_back(_overlay, _close_overlay)
	var fill := func(b: Dictionary) -> void:
		if not is_instance_valid(grid):
			return
		title.text = tr("WEEKLY HUNT  ·  %s") % str(b.get("week", ""))
		sub.text = str(b.get("prize", "")) if str(b.get("prize", "")) != "" else tr("Top hunters this week")
		for c in grid.get_children():
			c.queue_free()
		for h in ["#", tr("PLAYER"), tr("KILLS"), tr("TON")]:
			grid.add_child(UiTheme.label(h, 16, UiTheme.MUTED))
		for e in b.get("entries", []):
			grid.add_child(UiTheme.label(str(int(e.rank)), 20))
			grid.add_child(UiTheme.label(str(e.name), 20))
			grid.add_child(UiTheme.label(str(int(e.kills)), 20))
			grid.add_child(UiTheme.label(UiTheme.ton_text(int(e.tonMicro)), 20))
		if b.get("entries", []).is_empty():
			grid.add_child(UiTheme.label(tr("No kills yet this week. Be the first."), 18))
		if int(b.get("myRank", 0)) > 0:
			var mine := tr("You: #%d  ·  %d kills  ·  TON %s this week")
			if int(b.myKills) == 1:
				mine = tr("You: #%d  ·  %d kill  ·  TON %s this week")
			me.text = mine % [int(b.myRank), int(b.myKills), UiTheme.ton_text(int(b.myTonMicro))]
		else:
			me.text = tr("You: no kills yet this week")
	if not Net.leaderboard.is_empty():
		fill.call(Net.leaderboard)
	Net.leaderboard_received.connect(fill, CONNECT_ONE_SHOT)
	Net.request_leaderboard()


func _how_to_play() -> void:
	if _overlay:
		return
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(_overlay)
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
	I18n.dir(v)
	v.add_child(UiTheme.title(tr("HOW TO PLAY"), 30, UiTheme.GOLD))
	v.add_child(UiTheme.rule(700))
	for line in [
		tr("Left thumb: move.  Right thumb: drag to aim, FIRE also aims while held."),
		tr("Survive the waves. Kills and hits earn credits ($)."),
		tr("Buy weapons and ammo on the walls, or gamble on the SUPPLY CACHE under the green beam."),
		tr("Perk machines give lasting bonuses (health, reload, speed, swap) until you go down."),
		tr("Zombies may drop power-ups: INSTA-KILL, DOUBLE POINTS, MAX AMMO, NUKE, FIRE SALE. Walk over them."),
		tr("A downed teammate bleeds out in 30 s: stand next to them and hold REVIVE."),
		tr("If everyone is down, the game is over. Your best wave is saved to your Telegram account."),
		tr("INFECTION: soldiers against infected players. A soldier who falls turns; the infected come back after 5 s. Last soldier standing or the clock decides."),
	]:
		var l := UiTheme.label("•  " + line, 18)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	v.add_child(UiTheme.gold_button(tr("CLOSE"), _close_overlay))
	Platform.on_back(_overlay, _close_overlay)


## A thin XP bar with its numbers under it.
class XpBar extends Control:
	var value := 0
	var goal := 1
	var text := ""

	func _init() -> void:
		custom_minimum_size = Vector2(0, 26)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(v: int, g: int, t: String) -> void:
		value = v
		goal = maxi(1, g)
		text = t
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(0, 3, size.x, 6), Color(0.06, 0.055, 0.07))
		draw_rect(Rect2(0, 3, size.x * clampf(float(value) / float(goal), 0.0, 1.0), 6), UiTheme.GOLD)
		draw_rect(Rect2(0, 3, size.x, 6), UiTheme.BRASS_DARK, false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, 24), text, HORIZONTAL_ALIGNMENT_LEFT, size.x, 13, UiTheme.MUTED)
