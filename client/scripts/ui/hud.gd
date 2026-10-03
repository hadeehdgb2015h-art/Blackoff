class_name Hud
extends Control
## In-game HUD: health, ammo, wave, credits, interaction prompt, crosshair,
## hit markers, damage vignette, banners, team list, markers over downed
## teammates, revive progress, downed/bleed-out state and the game-over table.
## Reads state only; never changes gameplay.

signal retry_pressed
signal menu_pressed
signal challenge_pressed  ## game over: share the result with the invite link
signal streak(kills: int)  ## the local player chained kills (the game plays a sound)

## Kills chained within STREAK_GAP seconds of each other (what is called out: _streak_name).
const STREAK_GAP := 2.6

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
var _go_table: GridContainer
var _go_challenge: Button
var _team: TeamPanel
var _bots_seen := {}
var _puzzle_line: Label   ## a puzzle's words to the squad (phase 31)
var _puzzle_t := 0.0  ## AI soldiers in the squad (phase 30): id -> name, for join / leave toasts
var _markers: Markers
var _revive_back: ColorRect
var _revive_bar: ColorRect
var _revive_label: Label
var _boosts: Label
var _perks: Label
var _ton: Label
var _ton_pop: Label
var _ton_pop_t: float = 0.0
var _ton_game: int = 0   ## TON points (millionths) earned this game (display only; the server owns the real number)

var _dead_at: float = -1.0   ## infection: when the local infected player fell (respawn countdown)
var _fps_t: float = 0.0
var _world: SimWorld
var _banner_t: float = 0.0
var _callout: Label
var _scope: ScopeOverlay
var _boss_box: VBoxContainer   ## the boss's name and health bar, top centre, while one is alive
var _boss_name: Label
var _boss_fill: ColorRect
var _boss_back: ColorRect
var _callout_t: float = 0.0
var _streak: int = 0
var _streak_last: float = -100.0
var _toast_t: float = 0.0
var _pop_t: float = 0.0
var _pop_amount: int = 0
var _damage: float = 0.0


class Crosshair extends Control:
	var spread: float = 1.0
	var ads: float = 0.0       ## sighted amount: the hip cross gives way to a red dot
	var scoped: bool = false   ## the scope overlay draws its own reticle
	var hit_t: float = 0.0
	var hit_head: bool = false
	var hit_kill: bool = false

	func _process(delta: float) -> void:
		hit_t = maxf(0.0, hit_t - delta)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		if scoped:
			return
		if ads > 0.5:
			# sights up: a small red dot, as through a reflex sight
			draw_circle(c, 3.4, Color(0, 0, 0, 0.55))
			draw_circle(c, 2.3, Color(1.0, 0.22, 0.15, 0.95))
		else:
			var gap := 8.0 + spread * 6.0
			var col := Color(1, 1, 1, 0.85 * (1.0 - ads * 2.0))
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + d * gap, c + d * (gap + 10.0), Color(0, 0, 0, 0.6 * (1.0 - ads * 2.0)), 4.0)
				draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.0)
			draw_circle(c, 1.6, col)
		if hit_t > 0.0:
			var hc := Color(1, 0.25, 0.2) if hit_head or hit_kill else Color(1, 1, 1)
			hc.a = clampf(hit_t / 0.12, 0, 1)
			var r := 10.0 if not hit_kill else 14.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * r * 0.6, c + d * r * 1.4, hc, 3.0)


## Teammates under the health bar: name, health, DOWN with bleed-out, or DEAD.
class TeamPanel extends Control:
	var rows: Array = []  ## [{name, hp_k, state, bleed, revived, speaking}]
	var font: Font

	func _draw() -> void:
		var y := 0.0
		for r in rows:
			var col := Color(0.85, 0.85, 0.82)
			var tags := PackedStringArray([str(r.name)])  # the name, then status tags
			if r.get("infected", false):
				col = Color(0.45, 0.85, 0.5)
				tags.append(tr("RESPAWNING") if r.state == SimPlayer.State.DEAD else tr("INFECTED"))
			if r.get("speaking", false):
				# sound waves next to a talking teammate
				var c := Vector2(-14, y + 8)
				draw_circle(c, 2.5, Color(0.45, 0.85, 0.5))
				draw_arc(c, 6.0, -0.9, 0.9, 8, Color(0.45, 0.85, 0.5), 1.5, true)
				draw_arc(c, 10.0, -0.9, 0.9, 10, Color(0.45, 0.85, 0.5, 0.7), 1.5, true)
			if r.state == SimPlayer.State.DOWNED:
				col = UiTheme.ACCENT
				tags.append(tr("REVIVING") if r.revived else tr("DOWN %d") % ceili(r.bleed))
			elif r.state == SimPlayer.State.DEAD:
				col = Color(0.5, 0.5, 0.5)
				tags.append(tr("DEAD"))
			draw_rect(Rect2(0, y + 4, 150, 8), Color(0, 0, 0, 0.55))
			if r.state == SimPlayer.State.ALIVE:
				draw_rect(Rect2(1, y + 5, 148.0 * r.hp_k, 6), col)
			if r.get("infected", false) and r.state != SimPlayer.State.DEAD:
				tags = PackedStringArray([str(r.name), tr("INFECTED")])
			var text := "  ".join(tags)
			var x := 160.0
			var level := int(r.get("level", 0))
			if r.get("bot", false):
				# an AI soldier filling the squad (phase 30): a plain tag instead of a rank
				var tag := tr("AI")
				var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0
				draw_rect(Rect2(x, y + 1, tw, 16), Color(0.35, 0.6, 0.75, 0.85), false, 1.0)
				draw_string(font, Vector2(x + 5, y + 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.8, 0.95))
				x += tw + 8.0
			elif level > 0:
				# the teammate's rank insignia and level (phase 26)
				RankBadge.draw_insignia(self, Rect2(x, y - 1, 20, 20), Progression.rank_for(level))
				draw_string(font, Vector2(x + 22, y + 14), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.GOLD)
				x += 46.0
			draw_string(font, Vector2(x, y + 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
			y += 26.0


## Red cross over downed teammates, with distance; pinned to the screen edge
## with an arrow when they are behind the camera or off screen.
class Markers extends Control:
	var items: Array = []  ## [{pos: Vector2, on_screen: bool, dist: float, revived: bool}]
	var font: Font
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.65 + 0.35 * sin(_t * 6.0)
		for m in items:
			var col := Color(1, 1, 1, 0.95) if m.revived else Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, pulse)
			var p: Vector2 = m.pos
			draw_circle(p, 17, Color(0, 0, 0, 0.45))
			draw_rect(Rect2(p.x - 4, p.y - 12, 8, 24), col)
			draw_rect(Rect2(p.x - 12, p.y - 4, 24, 8), col)
			var label := tr("%d m") % roundi(m.dist)
			draw_string(font, p + Vector2(-20, 34), label, HORIZONTAL_ALIGNMENT_CENTER, 40, 16, col)
			if not m.on_screen:
				var c := size / 2.0
				var d: Vector2 = (p - c).normalized()
				var tip := p + d * 26.0
				var side := Vector2(-d.y, d.x) * 9.0
				draw_colored_polygon(PackedVector2Array([tip, p + d * 14.0 + side, p + d * 14.0 - side]), col)


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
	_wave_label = _top_centered(36, UiTheme.ACCENT, 12)
	_wave_label.add_theme_font_override("font", UiTheme.display_font())
	_wave_sub = _top_centered(20, UiTheme.MUTED, 60)
	_boosts = _top_centered(22, Color(1.0, 0.8, 0.3), 86)

	# Credits (top-right, left of the pause button)
	_credits = _right_label(28, UiTheme.GOLD, 24, 100)
	_credit_pop = _right_label(22, UiTheme.GOLD, 62, 100)
	_ton = _right_label(18, Color(0.55, 0.85, 1.0), 96, 100)
	_ton_pop = _right_label(18, Color(0.55, 0.85, 1.0), 122, 100)

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
	_banner = _centered(56, UiTheme.ACCENT, -120, true)
	_banner.add_theme_font_override("font", UiTheme.display_font())
	_toast = _centered(24, Color(1, 0.55, 0.45), 200)
	_build_boss_bar()
	_callout = _centered(44, UiTheme.GOLD, -200, true)
	_callout.add_theme_font_override("font", UiTheme.display_font())
	_callout.add_theme_constant_override("outline_size", 8)
	_callout.modulate.a = 0.0
	_downed = _centered(36, UiTheme.ACCENT, -40, true)
	_downed.add_theme_font_override("font", UiTheme.display_font())

	_fps = UiTheme.label("", 18, UiTheme.MUTED)
	_fps.position = Vector2(24, 52)
	add_child(_fps)

	_perks = UiTheme.label("", 18, Color(0.95, 0.9, 0.8))
	_perks.position = Vector2(24, 190)
	add_child(_perks)

	_team = TeamPanel.new()
	_team.font = ThemeDB.fallback_font
	_team.position = Vector2(24, 84)
	_team.size = Vector2(420, 120)
	_team.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_team)

	_markers = Markers.new()
	_markers.font = _team.font
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_markers)

	# Revive progress (under the crosshair)
	_revive_back = ColorRect.new()
	_revive_back.color = Color(0, 0, 0, 0.6)
	_revive_back.size = Vector2(320, 14)
	_revive_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_revive_back)
	_revive_bar = ColorRect.new()
	_revive_bar.color = Color(0.95, 0.95, 0.9)
	_revive_bar.size = Vector2(0, 8)
	_revive_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_revive_bar)
	_revive_label = _centered(22, UiTheme.TEXT, 64)

	_build_game_over()
	_apply_safe_area()


## Telegram's buttons and the phone's bars cover the edges: the HUD keeps clear
## of them; the crosshair and vignette stay on the real screen centre.
func _apply_safe_area() -> void:
	var view := get_viewport_rect().size
	var ins := Platform.safe_insets(view)
	offset_left = float(ins.left)
	offset_top = float(ins.top)
	offset_right = -float(ins.right)
	offset_bottom = -float(ins.bottom)
	for full in [_cross, _vignette]:
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.offset_left = -float(ins.left)
		full.offset_top = -float(ins.top)
		full.offset_right = float(ins.right)
		full.offset_bottom = float(ins.bottom)


func update_state(p: SimPlayer, w: SimWorld, interact: Dictionary, delta: float) -> void:
	_fade_puzzle(delta)
	_world = w
	_update_boss_bar(w)
	var hp_k := clampf(p.hp / p.max_hp, 0.0, 1.0)
	_hp_bar.size.x = 294.0 * hp_k
	_hp_bar.color = Color(0.85, 0.85, 0.82) if hp_k > 0.35 else UiTheme.ACCENT
	_hp_label.text = str(ceili(p.hp))
	var d := w.director
	var infection := w is NetWorld and (w as NetWorld).mode == 1
	if infection:
		_infection_top(p, w as NetWorld)
	else:
		match w.zone_state:
			SimWorld.ZoneState.WAVE:
				_wave_label.text = tr("WAVE %d") % d.wave
				_wave_sub.text = tr("%d left") % d.remaining()
			SimWorld.ZoneState.INTERMISSION:
				_wave_label.text = tr("WAVE %d") % d.wave if d.wave > 0 else tr("GET READY")
				_wave_sub.text = tr("next wave in %d") % ceili(maxf(0.0, d.phase_end - w.time))
			_:
				_wave_sub.text = ""
	_credits.text = "" if infection else "$ %d" % p.currency
	_ton.visible = false
	var wp := p.weapon()
	if wp:
		_ammo.text = "%d / %d" % [wp.mag, wp.reserve]
		_ammo.add_theme_color_override("font_color", UiTheme.ACCENT if wp.mag == 0 else UiTheme.TEXT)
		_weapon_name.text = I18n.name_of(str(wp.def.displayName))
	elif p.team == 1:
		_ammo.text = ""
		_weapon_name.text = tr("CLAWS")
	if p.is_reloading():
		_status.text = tr("RELOADING")
	elif wp and wp.mag == 0 and wp.reserve == 0:
		_status.text = tr("NO AMMO")
	elif infection and p.team == 1 and p.is_alive() and w.zone_state == SimWorld.ZoneState.WAVE:
		_status.text = tr("INFECTED  ·  hunt the soldiers")
	else:
		_status.text = ""
	if interact.is_empty():
		_prompt.text = ""
	else:
		match interact.action:
			"box":
				_prompt.text = tr("Open Supply Cache  $%d") % interact.cost
			"take":
				_prompt.text = tr("Take %s") % _offer_name(w, interact, "weapons")
			"wait":
				_prompt.text = _wait_text(str(interact.label))
			"perk":
				var perk := _offer_name(w, interact, "perks")
				_prompt.text = (tr("%s  (owned)") % perk) if interact.full else tr("Buy %s  $%d") % [perk, interact.cost]
			"revive":
				var downed: SimPlayer = w.players.get(interact.get("target", -1))
				_prompt.text = (tr("Hold to revive %s") % downed.name) if downed else str(interact.label)
			"weapon":
				_prompt.text = tr("Buy %s  $%d") % [_offer_name(w, interact, "weapons"), interact.cost]
			_:
				var gun := _offer_name(w, interact, "weapons")
				if interact.full:
					_prompt.text = tr("Refill Ammo: %s  $%d  (full)") % [gun, interact.cost]
				else:
					_prompt.text = tr("Refill Ammo: %s  $%d") % [gun, interact.cost]
		_prompt.add_theme_color_override("font_color", UiTheme.TEXT if interact.affordable and not interact.full else UiTheme.MUTED)
	var boosts := PackedStringArray()
	for t in ["instaKill", "doublePoints", "fireSale"]:
		var left := w.powerups.seconds_left(t)
		if left > 0:
			boosts.append("%s %d" % [I18n.name_of(str(w.constants.powerups.types[t].displayName)), left])
	_boosts.text = "   ".join(boosts)
	var chips := PackedStringArray()
	for id in p.perks:
		chips.append(I18n.name_of(str(w.defs.perks.get(id, {}).get("displayName", id))).to_upper())
	_perks.text = "  ·  ".join(chips)
	_cross.spread = 1.6 if p.moving else 1.0
	_cross.visible = p.is_alive()
	_announce_bots(w)
	var mates := 0
	var rows := []
	var speaking: Array = Net.voice_speaking() if Net.online_requested else []
	for o in w.players.values():
		if o == p:
			continue
		if o.is_alive():
			mates += 1
		rows.append({"name": o.name, "hp_k": clampf(o.hp / maxf(1.0, o.max_hp), 0.0, 1.0), "state": o.state,
			"bleed": w.bleedout_left(o), "revived": w.is_being_revived(o), "speaking": o.id in speaking, "infected": o.team == 1,
			"level": int(w.levels.get(o.id, 0)) if "levels" in w else 0,
			"bot": "levels" in w and w.levels.has(o.id) and int(w.levels[o.id]) == 0})
	_team.rows = rows
	_team.queue_redraw()
	var prog := w.revive_progress(p)
	if infection and p.state == SimPlayer.State.DEAD:
		var left := float(w.constants.infection.zombieRespawnSec) - (w.time - _dead_at) if _dead_at >= 0.0 else 0.0
		_downed.text = tr("YOU FELL\nBack in %d") % ceili(maxf(0.0, left))
	elif p.state == SimPlayer.State.DOWNED:
		var line := tr("BEING REVIVED") if w.is_being_revived(p) else (tr("Hold on, a teammate can revive you") if mates > 0 else tr("No one left to revive you"))
		_downed.text = tr("YOU ARE DOWN  %d\n%s") % [ceili(w.bleedout_left(p)), line]
	elif p.state == SimPlayer.State.DEAD:
		_downed.text = tr("YOU BLED OUT\nBack at the next wave") if mates > 0 else ""
	else:
		_downed.text = ""
	var show_bar := prog > 0.0
	_revive_back.visible = show_bar
	_revive_bar.visible = show_bar
	if show_bar:
		var c := size / 2.0 + Vector2(0, 50)
		_revive_back.position = c - Vector2(160, 7)
		_revive_bar.position = c - Vector2(157, 4)
		_revive_bar.size.x = 314.0 * prog
		var target: SimPlayer = w.players.get(p.revive_target)
		_revive_label.text = (tr("REVIVING %s") % target.name) if p.is_alive() and target else ""
	else:
		_revive_label.text = ""
	_fps.visible = Settings.show_fps
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.5
		_fps.text = "%d FPS  ·  %s  ·  %d draws" % [Engine.get_frames_per_second(), Settings.effective_quality(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
	_tick(delta)


## Centre message for connection states ("Connecting...", errors); "" hides it.
func show_status(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0 if text != "" else 0.0


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
				_on_local_kill(bool(e.get("head", false)))
				# TON is counted quietly and shown once, at game over: a "+0.00001 TON"
				# flash on every kill looked cheap (owner, phase 18)
				if Net.ton_per_kill > 0 and Net.online_requested:
					_ton_game += Net.ton_per_kill
		"player_damaged":
			if e.pid == local_pid:
				_damage = minf(1.0, _damage + float(e.amount) / 35.0)
		"wave_started":
			_show_banner(tr("WAVE %d") % e.wave)
		"wave_cleared":
			_show_banner(tr("WAVE %d CLEARED") % e.wave)
		"currency":
			if e.pid == local_pid and e.amount > 0:
				_pop_amount = (_pop_amount if _pop_t > 0.0 else 0) + int(e.amount)
				_pop_t = 1.0
		"purchase_denied":
			if e.pid == local_pid:
				_show_toast(tr("Not enough credits") if e.reason == "funds" else tr("Ammo already full"))
		"purchase":
			if e.pid == local_pid:
				_show_toast(tr("Purchased"))
		"box_offer":
			if e.pid == local_pid:
				_show_toast(tr("Take it before it's gone!"))
		"player_revived":
			if e.pid == local_pid:
				_show_toast(tr("You were revived"))
			elif e.by == local_pid:
				_show_toast(tr("Teammate revived"))
		"player_respawned":
			if e.pid == local_pid:
				_show_banner(tr("BACK IN THE FIGHT"))
		"player_hit":
			if e.pid == local_pid:
				_cross.hit_t = 0.12
				_cross.hit_head = e.head
				_cross.hit_kill = false
		"player_killed":
			if e.pid == local_pid:
				_dead_at = _world.time if _world else 0.0
			elif e.by == local_pid:
				_cross.hit_t = 0.18
				_cross.hit_kill = true
				_on_local_kill(bool(e.get("head", false)))
		"infected":
			if e.pid == local_pid:
				_show_banner(tr("YOU ARE INFECTED"))
				_show_toast(tr("Hunt the soldiers: tap ATTACK next to them"))
			else:
				var who: SimPlayer = _world.players.get(e.pid) if _world else null
				_show_toast((tr("%s was infected") % who.name) if who else tr("A soldier was infected"))
		"round_start":
			_show_banner(tr("ROUND %d") % e.round)
			_show_toast(tr("%d infected among you. Survive %d:%02d") % [e.infected, int(e.seconds) / 60, int(e.seconds) % 60])
		"round_end":
			_show_banner(tr("SOLDIERS WIN") if e.soldiersWin else tr("INFECTED WIN"))
		"powerup_taken":
			var pdef: Dictionary = SharedData.constants.get("powerups", {}).get("types", {}).get(str(e.ptype), {})
			_show_banner(I18n.name_of(str(pdef.get("displayName", str(e.ptype).to_upper()))))


## Infection mode: round, clock and soldiers left (or the lobby countdown).
func _infection_top(p: SimPlayer, nw: NetWorld) -> void:
	var left := ceili(nw.phase_left)
	match nw.zone_state:
		SimWorld.ZoneState.WAVE:
			_wave_label.text = tr("ROUND %d   %d:%02d") % [nw.director.wave, left / 60, left % 60]
			_wave_sub.text = (tr("%d soldier left") if nw.soldiers_left == 1 else tr("%d soldiers left")) % nw.soldiers_left
		SimWorld.ZoneState.INTERMISSION:
			_wave_label.text = tr("SOLDIERS WIN") if nw.round_result == 1 else tr("INFECTED WIN")
			_wave_sub.text = tr("next round in %d") % left
		_:
			_wave_label.text = tr("INFECTION")
			var need := int(nw.constants.infection.minPlayers)
			_wave_sub.text = (tr("Starting in %d") % left) if nw.phase_left > 0.0 else tr("Waiting for players  %d / %d") % [nw.players.size(), need]


## Positions of downed teammates on screen (computed by the game from its camera).
func set_markers(items: Array) -> void:
	_markers.items = items


func show_game_over(wave: int, p: SimPlayer, scores: Array = []) -> void:
	_go_stats.text = tr("Reached wave %d") % wave
	if _ton_game > 0:
		_go_stats.text += "\n" + (tr("TON earned this game: %s  (credited to your weekly hunt)") % UiTheme.ton_text(_ton_game))
	if Net.online_requested and p:
		# experience (phase 26): the server's count arrives with the profile after the game
		_go_stats.text += "\n" + (tr("Experience: +%d XP") % Progression.xp_for(p.kills, p.headshots, wave, 0.0, 0))
	for c in _go_table.get_children():
		c.queue_free()
	if scores.is_empty():
		scores = [{"id": p.id, "name": p.name, "kills": p.kills, "headshots": p.headshots, "downs": p.downs, "revives": p.revives}]
	scores.sort_custom(func(a, b): return int(a.kills) > int(b.kills))
	for h in [tr("PLAYER"), tr("KILLS"), tr("HEADSHOTS"), tr("DOWNS"), tr("REVIVES")]:
		_go_table.add_child(UiTheme.label(h, 18, UiTheme.MUTED))
	for r in scores:
		var col := UiTheme.ACCENT if int(r.id) == p.id else UiTheme.TEXT
		_go_table.add_child(UiTheme.label(str(r.name), 22, col))
		for k in ["kills", "headshots", "downs", "revives"]:
			var l := UiTheme.label(str(int(r[k])), 22, col)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_go_table.add_child(l)
	_go_challenge.visible = Social.can_invite() or Net.status in ["ready", "in_zone"]
	_game_over.visible = true


func hide_game_over() -> void:
	_game_over.visible = false


func _tick(delta: float) -> void:
	_damage = maxf(0.0, _damage - delta * 0.8)
	_vignette.modulate.a = _damage
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	if _callout_t > 0.0:
		_callout_t -= delta
		_callout.modulate.a = clampf(_callout_t / 0.35, 0.0, 1.0)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	if _pop_t > 0.0:
		_pop_t -= delta
		_credit_pop.text = "+%d" % _pop_amount
		_credit_pop.modulate.a = clampf(_pop_t / 0.4, 0.0, 1.0)
	else:
		_credit_pop.text = ""
	if _ton_pop_t > 0.0:
		_ton_pop_t -= delta
		_ton_pop.modulate.a = clampf(_ton_pop_t / 0.5, 0.0, 1.0)
	else:
		_ton_pop.text = ""


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner_t = 2.2
	_pop(_banner, 1.35)


## Kill streaks: kills less than STREAK_GAP apart chain up and are called out
## (DOUBLE KILL ... GODLIKE); a lone head kill gets a short HEADSHOT.
func _on_local_kill(head: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_streak = _streak + 1 if now - _streak_last <= STREAK_GAP else 1
	_streak_last = now
	var called := _streak_name(_streak)
	if called != "":
		_callout.text = called
		_callout.add_theme_color_override("font_color", UiTheme.GOLD if _streak < 5 else UiTheme.ACCENT)
		_callout_t = 1.6
		_pop(_callout, 1.8)
		streak.emit(_streak)
	elif head and _callout_t <= 0.2:
		_callout.text = tr("HEADSHOT")
		_callout.add_theme_color_override("font_color", UiTheme.TEXT)
		_callout_t = 0.7
		_pop(_callout, 1.25)


## What a chain of n kills is called out as ("" for none).
func _streak_name(n: int) -> String:
	match n:
		2:
			return tr("DOUBLE KILL")
		3:
			return tr("TRIPLE KILL")
		4:
			return tr("QUAD KILL")
		5:
			return tr("RAMPAGE")
		7:
			return tr("MASSACRE")
		10:
			return tr("UNSTOPPABLE")
		15:
			return tr("GODLIKE")
	return ""


## The translated display name of the weapon or perk an interaction offers
## (defs group "weapons" or "perks"); falls back to the sim's English label.
func _offer_name(w: SimWorld, interact: Dictionary, group: String) -> String:
	var def: Dictionary = w.defs.get(group, {}).get(str(interact.get("item", "")), {})
	return I18n.name_of(str(def.get("displayName", str(interact.label).trim_prefix("Ammo: "))))


## The sim's "wait" prompts (supply cache busy) in the interface language.
func _wait_text(label: String) -> String:
	match label:
		"Rolling...":
			return tr("Rolling...")
		"Supply Cache in use":
			return tr("Supply Cache in use")
	return label


## A boss's title for the bar and banners: its zombie display name, translated,
## in capitals (THE WARDEN). Found by zombie type, or by the visuals' bossName.
func _boss_title(type: String, boss_name := "") -> String:
	if type == "":
		for id in SharedData.zombies:
			if str(Visuals.zombie(str(id)).get("bossName", "")) == boss_name:
				type = str(id)
				break
	var def: Dictionary = SharedData.get_zombie(type)
	if def.has("displayName"):
		return I18n.name_of(str(def.displayName)).to_upper()
	return boss_name if boss_name != "" else str(Visuals.zombie(type).get("bossName", type))


## A label punches in: starts big and settles to its size.
func _pop(l: Label, from_scale: float) -> void:
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2.ONE * from_scale
	l.modulate.a = 1.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_toast(text: String, sec := 1.6) -> void:
	_toast.text = text
	_toast_t = sec


## A short message under the crosshair (the game scene's voice and invite notes).
func show_toast(text: String, sec := 2.4) -> void:
	if text != "":
		_show_toast(text, sec)


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


func _build_boss_bar() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_box.offset_left = -270
	_boss_box.offset_right = 270
	_boss_box.offset_top = 112
	_boss_box.add_theme_constant_override("separation", 4)
	_boss_box.visible = false
	add_child(_boss_box)
	_boss_name = UiTheme.label("", 22, Color(1.0, 0.42, 0.34))
	_boss_name.add_theme_font_override("font", UiTheme.display_font())
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_back = ColorRect.new()
	_boss_back.color = Color(0.05, 0.02, 0.02, 0.85)
	_boss_back.custom_minimum_size = Vector2(540, 14)
	_boss_box.add_child(_boss_back)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(0.78, 0.08, 0.06)
	_boss_fill.size = Vector2(540, 14)
	_boss_back.add_child(_boss_fill)


## Shows the strongest living boss's health (or hides the bar).
func _update_boss_bar(w: SimWorld) -> void:
	var boss: SimZombie = null
	for z in w.zombies.values():
		if Visuals.zombie(z.type).has("bossName") and (boss == null or z.hp > boss.hp):
			boss = z
	_boss_box.visible = boss != null
	if boss:
		_boss_name.text = _boss_title(boss.type)
		_boss_fill.size.x = 540.0 * clampf(boss.hp / maxf(1.0, boss.max_hp), 0.0, 1.0)


## Aiming state for the crosshair and the scope overlay (phase 22).
func set_aim(ads: float, scoped: bool, delta: float) -> void:
	_cross.ads = ads
	_cross.scoped = scoped
	if _scope == null:
		_scope = ScopeOverlay.new()
		add_child(_scope)
		move_child(_scope, 0)  # under the HUD text and buttons
	_scope.set_scoped(scoped, delta)


## A boss has come: a banner and a call-out.
func boss_arrived(boss_name: String) -> void:
	_show_banner(tr("%s HAS RISEN") % _boss_title("", boss_name))


func boss_fell(boss_name: String) -> void:
	_show_banner(tr("%s FALLS") % _boss_title("", boss_name))


func _build_game_over() -> void:
	_game_over = PanelContainer.new()
	_game_over.visible = false
	_game_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	I18n.dir(v)  # Arabic: right-to-left table and button row
	_game_over.add_child(v)
	var title := UiTheme.title(tr("OVERRUN"), 52, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var r := UiTheme.rule(420)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(r)
	_go_stats = UiTheme.label("", 26)
	_go_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_go_stats)
	_go_table = GridContainer.new()
	_go_table.columns = 5
	_go_table.add_theme_constant_override("h_separation", 28)
	_go_table.add_theme_constant_override("v_separation", 6)
	v.add_child(_go_table)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiTheme.big_button(tr("PLAY AGAIN"), func(): retry_pressed.emit()))
	_go_challenge = UiTheme.gold_button(tr("CHALLENGE FRIENDS"), func(): challenge_pressed.emit())
	row.add_child(_go_challenge)
	row.add_child(UiTheme.button(tr("MAIN MENU"), func(): menu_pressed.emit()))
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


## Toasts when an AI soldier joins the squad or makes room for a player (phase 30).
func _announce_bots(w) -> void:
	if not ("levels" in w):
		return
	var now := {}
	for id in w.levels:
		if int(w.levels[id]) == 0 and w.players.has(id):
			now[id] = str(w.roster.get(id, ""))
	for id in now:
		if not _bots_seen.has(id):
			show_toast(tr("AI soldier %s joined your squad") % now[id], 3.0)
	for id in _bots_seen:
		if not now.has(id):
			show_toast(tr("%s left to make room for a player") % _bots_seen[id], 3.0)
	_bots_seen = now


## A line from the puzzles (phase 31): under the wave counter, gold when it
## matters (big), long enough to read.
func show_puzzle(text: String, big: bool) -> void:
	if _puzzle_line == null:
		_puzzle_line = UiTheme.label("", 20, UiTheme.TEXT)
		_puzzle_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_puzzle_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_puzzle_line.anchor_left = 0.18
		_puzzle_line.anchor_right = 0.82
		_puzzle_line.offset_top = 96
		_puzzle_line.offset_bottom = 190
		_puzzle_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_puzzle_line.add_theme_constant_override("outline_size", 6)
		_puzzle_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_puzzle_line)
	_puzzle_line.text = text
	_puzzle_line.add_theme_font_size_override("font_size", 23 if big else 19)
	_puzzle_line.add_theme_color_override("font_color", UiTheme.GOLD if big else UiTheme.TEXT)
	_puzzle_line.modulate.a = 1.0
	_puzzle_t = 7.0 if big else 4.5
	_pop(_puzzle_line, 1.12)


func _fade_puzzle(delta: float) -> void:
	if _puzzle_line == null or _puzzle_t <= 0.0:
		return
	_puzzle_t -= delta
	_puzzle_line.modulate.a = clampf(_puzzle_t / 0.8, 0.0, 1.0)
