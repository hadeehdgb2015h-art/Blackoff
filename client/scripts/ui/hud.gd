class_name Hud
extends Control
## In-game HUD: health, ammo, wave, credits, interaction prompt, crosshair,
## hit markers, damage vignette, banners, downed and game-over states.
## Reads state only; never changes gameplay.

signal retry_pressed
signal menu_pressed

var _hp_bar: ColorRect
var _hp_back: ColorRect
var _hp_label: Label
var _wave_label: Label
var _wave_sub: Label
var _credits: Label
var _credit_pop: Label
var _ammo: Label
var _weapon_name: Label
var _status: Label
var _prompt: Label
var _banner: Label
var _toast: Label
var _fps: Label
var _vignette: TextureRect
var _downed: Label
var _cross: Crosshair
var _game_over: PanelContainer
var _go_stats: Label

var _banner_t: float = 0.0
var _toast_t: float = 0.0
var _pop_t: float = 0.0
var _pop_amount: int = 0
var _damage: float = 0.0


class Crosshair extends Control:
	var spread: float = 1.0
	var hit_t: float = 0.0
	var hit_head: bool = false
	var hit_kill: bool = false

	func _process(delta: float) -> void:
		hit_t = maxf(0.0, hit_t - delta)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var gap := 8.0 + spread * 6.0
		var col := Color(1, 1, 1, 0.85)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * gap, c + d * (gap + 10.0), Color(0, 0, 0, 0.6), 4.0)
			draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.0)
		draw_circle(c, 1.6, col)
		if hit_t > 0.0:
			var hc := Color(1, 0.25, 0.2) if hit_head or hit_kill else Color(1, 1, 1)
			hc.a = clampf(hit_t / 0.12, 0, 1)
			var r := 10.0 if not hit_kill else 14.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * r * 0.6, c + d * r * 1.4, hc, 3.0)


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_vignette = TextureRect.new()
	_vignette.texture = _vignette_tex()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_cross = Crosshair.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)

	# Health (top-left)
	_hp_back = ColorRect.new()
	_hp_back.color = Color(0, 0, 0, 0.55)
	_hp_back.position = Vector2(24, 24)
	_hp_back.size = Vector2(300, 22)
	_hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_back)
	_hp_bar = ColorRect.new()
	_hp_bar.color = Color(0.85, 0.85, 0.82)
	_hp_bar.position = Vector2(27, 27)
	_hp_bar.size = Vector2(294, 16)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bar)
	_hp_label = UiTheme.label("100", 20)
	_hp_label.position = Vector2(332, 19)
	add_child(_hp_label)

	# Wave (top-centre)
	_wave_label = _top_centered(40, UiTheme.ACCENT, 10)
	_wave_sub = _top_centered(20, UiTheme.MUTED, 60)

	# Credits (top-right, left of the pause button)
	_credits = _right_label(28, UiTheme.GOLD, 24, 100)
	_credit_pop = _right_label(22, UiTheme.GOLD, 62, 100)

	# Ammo (right, above the fire button)
	_ammo = _right_label(40, UiTheme.TEXT, 0, 40)
	_ammo.anchor_top = 1.0
	_ammo.anchor_bottom = 1.0
	_ammo.offset_top = -330
	_ammo.offset_bottom = -280
	_ammo.offset_right = -190
	_weapon_name = _right_label(20, UiTheme.MUTED, 0, 40)
	_weapon_name.anchor_top = 1.0
	_weapon_name.anchor_bottom = 1.0
	_weapon_name.offset_top = -284
	_weapon_name.offset_bottom = -256
	_weapon_name.offset_right = -190
	_status = _centered(26, UiTheme.ACCENT, 70)

	_prompt = _centered(26, UiTheme.TEXT, 150)
	_banner = _centered(64, UiTheme.ACCENT, -120, true)
	_toast = _centered(24, Color(1, 0.55, 0.45), 200)
	_downed = _centered(40, UiTheme.ACCENT, -40, true)

	_fps = UiTheme.label("", 18, UiTheme.MUTED)
	_fps.position = Vector2(24, 52)
	add_child(_fps)

	_build_game_over()


func update_state(p: SimPlayer, w: SimWorld, interact: Dictionary, delta: float) -> void:
	var hp_k := clampf(p.hp / p.max_hp, 0.0, 1.0)
	_hp_bar.size.x = 294.0 * hp_k
	_hp_bar.color = Color(0.85, 0.85, 0.82) if hp_k > 0.35 else UiTheme.ACCENT
	_hp_label.text = str(ceili(p.hp))
	var d := w.director
	match w.zone_state:
		SimWorld.ZoneState.WAVE:
			_wave_label.text = "WAVE %d" % d.wave
			_wave_sub.text = "%d left" % d.remaining()
		SimWorld.ZoneState.INTERMISSION:
			_wave_label.text = "WAVE %d" % d.wave if d.wave > 0 else "GET READY"
			_wave_sub.text = "next wave in %d" % ceili(maxf(0.0, d.phase_end - w.time))
		_:
			_wave_sub.text = ""
	_credits.text = "$ %d" % p.currency
	var wp := p.weapon()
	if wp:
		_ammo.text = "%d / %d" % [wp.mag, wp.reserve]
		_ammo.add_theme_color_override("font_color", UiTheme.ACCENT if wp.mag == 0 else UiTheme.TEXT)
		_weapon_name.text = str(wp.def.displayName)
	if p.is_reloading():
		_status.text = "RELOADING"
	elif wp and wp.mag == 0 and wp.reserve == 0:
		_status.text = "NO AMMO"
	else:
		_status.text = ""
	if interact.is_empty():
		_prompt.text = ""
	else:
		match interact.action:
			"box":
				_prompt.text = "Open Supply Cache  $%d" % interact.cost
			"take":
				_prompt.text = "Take %s" % interact.label
			"wait":
				_prompt.text = "Supply Cache in use"
			_:
				var verb := "Buy" if interact.action == "weapon" else "Refill"
				var suffix := "  (full)" if interact.full else ""
				_prompt.text = "%s %s  $%d%s" % [verb, interact.label, interact.cost, suffix]
		_prompt.add_theme_color_override("font_color", UiTheme.TEXT if interact.affordable and not interact.full else UiTheme.MUTED)
	_cross.spread = 1.6 if p.moving else 1.0
	_cross.visible = p.is_alive()
	if p.state == SimPlayer.State.DOWNED:
		var left := float(w.constants.player.downedBleedoutSec) - (w.time - p.downed_time)
		_downed.text = "YOU ARE DOWN\n%d" % ceili(maxf(0.0, left))
	else:
		_downed.text = ""
	_fps.visible = Settings.show_fps
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	_tick(delta)


func on_event(e: Dictionary, local_pid: int) -> void:
	match e.type:
		"zombie_hit":
			if e.pid == local_pid:
				_cross.hit_t = 0.12
				_cross.hit_head = e.head
				_cross.hit_kill = false
		"zombie_killed":
			if e.pid == local_pid:
				_cross.hit_t = 0.18
				_cross.hit_kill = true
		"player_damaged":
			if e.pid == local_pid:
				_damage = minf(1.0, _damage + float(e.amount) / 35.0)
		"wave_started":
			_show_banner("WAVE %d" % e.wave)
		"wave_cleared":
			_show_banner("WAVE %d CLEARED" % e.wave)
		"currency":
			if e.pid == local_pid and e.amount > 0:
				_pop_amount = (_pop_amount if _pop_t > 0.0 else 0) + int(e.amount)
				_pop_t = 1.0
		"purchase_denied":
			if e.pid == local_pid:
				_show_toast("Not enough credits" if e.reason == "funds" else "Ammo already full")
		"purchase":
			if e.pid == local_pid:
				_show_toast("Purchased")
		"box_offer":
			if e.pid == local_pid:
				_show_toast("Take it before it's gone!")


func show_game_over(wave: int, p: SimPlayer) -> void:
	_go_stats.text = "Reached wave %d\nKills %d   Headshots %d" % [wave, p.kills, p.headshots]
	_game_over.visible = true


func hide_game_over() -> void:
	_game_over.visible = false


func _tick(delta: float) -> void:
	_damage = maxf(0.0, _damage - delta * 0.8)
	_vignette.modulate.a = _damage
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	if _pop_t > 0.0:
		_pop_t -= delta
		_credit_pop.text = "+%d" % _pop_amount
		_credit_pop.modulate.a = clampf(_pop_t / 0.4, 0.0, 1.0)
	else:
		_credit_pop.text = ""


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner_t = 2.2


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 1.6


func _top_centered(size: int, color: Color, top: float) -> Label:
	var l := UiTheme.label("", size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.offset_top = top
	l.offset_bottom = top + size + 12
	add_child(l)
	return l


func _right_label(size: int, color: Color, top: float, right_margin: float) -> Label:
	var l := UiTheme.label("", size, color)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.offset_left = -420
	l.offset_right = -right_margin
	l.offset_top = top
	l.offset_bottom = top + size + 12
	add_child(l)
	return l


func _centered(size: int, color: Color, y_from_center: float, from_middle := false) -> Label:
	var l := UiTheme.label("", size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 0.5 if from_middle else 0.5
	l.anchor_bottom = l.anchor_top
	l.offset_top = y_from_center
	l.offset_bottom = y_from_center + size * 2.6
	add_child(l)
	return l


func _build_game_over() -> void:
	_game_over = PanelContainer.new()
	_game_over.visible = false
	_game_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_game_over.add_child(v)
	var title := UiTheme.label("OVERRUN", 56, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_go_stats = UiTheme.label("", 26)
	_go_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_go_stats)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiTheme.button("Play again", func(): retry_pressed.emit()))
	row.add_child(UiTheme.button("Main menu", func(): menu_pressed.emit()))
	v.add_child(row)
	add_child(_game_over)


static func _vignette_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0, 0, 0))
	g.add_point(0.55, Color(0.6, 0, 0, 0.0))
	g.set_color(g.get_point_count() - 1, Color(0.7, 0.02, 0.0, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 0.5)
	t.width = 128
	t.height = 128
	return t
