class_name DailyPanel
extends Control
## Daily reward and missions (phase 23), opened from the menu. Shows the 7-day
## streak calendar with today's reward to claim, and today's three missions with
## their progress. Everything comes from the server (`Net.daily`); CLAIM only
## asks, the server decides and pays TON points.

signal closed

var _tiles: Array[DayTile] = []
var _claim: Button
var _status: Label
var _reset: Label
var _rows: VBoxContainer
var _bonus: Label
var _gain: Label
var _reset_at := 0.0   ## seconds (ticks clock) when the day turns


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(20))
	panel.custom_minimum_size = Vector2(740, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)
	I18n.dir(v)

	var head := HBoxContainer.new()
	head.add_child(UiTheme.title(tr("DAILY REWARD"), 28, UiTheme.GOLD))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_reset = UiTheme.label("", 15, UiTheme.MUTED)
	head.add_child(_reset)
	v.add_child(head)
	v.add_child(UiTheme.rule(700))

	var days := HBoxContainer.new()
	days.add_theme_constant_override("separation", 8)
	days.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 7:
		var t := DayTile.new()
		t.day = i + 1
		_tiles.append(t)
		days.add_child(t)
	v.add_child(days)

	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 14)
	_claim = UiTheme.big_button(tr("CLAIM"), _on_claim)
	_claim.add_theme_font_size_override("font_size", 22)
	act.add_child(_claim)
	_status = UiTheme.label("", 16, UiTheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	act.add_child(_status)
	v.add_child(act)

	v.add_child(UiTheme.rule(700, UiTheme.BRASS_DARK))
	v.add_child(UiTheme.title(tr("DAILY MISSIONS"), 20, UiTheme.GOLD))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	v.add_child(_rows)
	_bonus = UiTheme.label("", 16, UiTheme.MUTED)
	v.add_child(_bonus)
	var close := UiTheme.gold_button(tr("CLOSE"), _close)
	Platform.on_back(self, _close)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(close)

	# "+0.005 TON" rises from the claimed day
	_gain = UiTheme.title("", 30, UiTheme.GOLD)
	_gain.add_theme_constant_override("outline_size", 6)
	_gain.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_gain.visible = false
	add_child(_gain)

	Net.daily_received.connect(_on_daily)
	if Net.daily.is_empty():
		_status.text = tr("Loading…") if Net.status in ["ready", "in_zone"] else tr("Open the game from the Telegram bot to collect daily rewards.")
		_claim.disabled = true
	else:
		_fill(Net.daily)
	Net.request_daily()
	print("[menu] daily panel opened")


func _process(_delta: float) -> void:
	if _reset_at <= 0.0:
		return
	var left := int(maxf(0.0, _reset_at - Time.get_ticks_msec() / 1000.0))
	var text := tr("New day in %dh %02dm") % [left / 3600, (left % 3600) / 60] if left >= 60 else tr("New day in %ds") % left
	if _reset.text != text:
		_reset.text = text


func _on_claim() -> void:
	_claim.disabled = true
	_claim.text = "…"
	Net.claim_daily()


func _on_daily(d: Dictionary) -> void:
	_fill(d)
	if int(d.get("paidMicro", 0)) > 0 and int(d.get("paidKind", 0)) == 1:
		var tile := _tiles[clampi(int(d.get("streak", 1)) - 1, 0, 6)]
		tile.flash()
		_rise(tr("+%s TON") % UiTheme.ton_text(int(d.paidMicro)), tile.get_global_rect().get_center())
		Audio.ui_sound("buy", -4.0)


func _fill(d: Dictionary) -> void:
	var can := bool(d.get("canClaim", false))
	var next := int(d.get("nextDay", 1))
	var streak := int(d.get("streak", 0))
	var rewards: Array = d.get("rewards", [])
	for i in 7:
		var t := _tiles[i]
		t.reward = UiTheme.ton_text(int(rewards[i].tonMicro)) if i < rewards.size() else ""
		if can:
			t.state = DayTile.TAKEN if i + 1 < next else (DayTile.TODAY if i + 1 == next else DayTile.LATER)
		else:
			var tomorrow := streak % 7 + 1
			t.state = DayTile.TAKEN if i + 1 <= streak else (DayTile.TOMORROW if i + 1 == tomorrow else DayTile.LATER)
			if streak == 7:  # the calendar is complete: tomorrow starts again at day 1
				t.state = DayTile.TAKEN
		t.queue_redraw()
	_claim.disabled = not can
	_claim.text = tr("CLAIM DAY %d") % next if can else tr("CLAIMED")
	if can:
		_status.text = tr("Come back every day: the reward grows to day 7. Miss a day and it starts again.") if next == 1 \
			else tr("Day %d in a row. Keep the streak going!") % next
	else:
		_status.text = tr("Day %d taken. Come back tomorrow for day %d.") % [streak, streak % 7 + 1]
	_reset_at = Time.get_ticks_msec() / 1000.0 + float(d.get("resetSec", 0))

	for c in _rows.get_children():
		c.queue_free()
	for m in d.get("missions", []):
		_rows.add_child(_mission_row(m))
	if d.get("missions", []).is_empty():
		_rows.add_child(UiTheme.label(tr("No missions today."), 16, UiTheme.MUTED))
	if bool(d.get("bonusDone", false)):
		_bonus.text = tr("All three done: bonus +%s TON paid. New missions tomorrow.") % UiTheme.ton_text(int(d.get("bonusMicro", 0)))
		_bonus.add_theme_color_override("font_color", UiTheme.GREEN)
	else:
		_bonus.text = tr("Finish all three for a bonus of +%s TON. Missions count online games.") % UiTheme.ton_text(int(d.get("bonusMicro", 0)))
		_bonus.add_theme_color_override("font_color", UiTheme.MUTED)


## A mission's line; kinds follow the protocol's missionKind order
## (kills, headshots, wave, boss, games).
static func mission_text(kind: int, goal: int) -> String:
	match clampi(kind, 0, 4):
		0: return String(TranslationServer.translate("Kill %d zombies")) % goal
		1: return String(TranslationServer.translate("Land %d headshot kills")) % goal
		2: return String(TranslationServer.translate("Reach wave %d")) % goal
		3:
			if goal > 1:
				return String(TranslationServer.translate("Slay the Warden %d times")) % goal
			return String(TranslationServer.translate("Slay the Warden"))
	return String(TranslationServer.translate("Finish %d online games")) % goal


func _mission_row(m: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	var done := bool(m.done)
	var text := UiTheme.label(mission_text(int(m.kind), int(m.goal)), 18, UiTheme.GREEN if done else UiTheme.TEXT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	line.add_child(UiTheme.label(tr("DONE  +%s TON") % UiTheme.ton_text(int(m.tonMicro)) if done else tr("+%s TON") % UiTheme.ton_text(int(m.tonMicro)),
		16, UiTheme.GREEN if done else UiTheme.GOLD))
	box.add_child(line)
	var bar := ProgressLine.new()
	bar.value = int(m.progress)
	bar.goal = maxi(1, int(m.goal))
	bar.done = done
	box.add_child(bar)
	return box


func _rise(text: String, at: Vector2) -> void:
	_gain.text = text
	_gain.visible = true
	_gain.reset_size()
	_gain.position = at - _gain.size / 2.0
	_gain.modulate.a = 1.0
	var tw := _gain.create_tween().set_parallel()
	tw.tween_property(_gain, "position:y", _gain.position.y - 70.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_gain, "modulate:a", 0.0, 0.5).set_delay(0.7)


## One day of the calendar: number, reward and its state.
class DayTile extends Control:
	const TAKEN := 0
	const TODAY := 1
	const TOMORROW := 2
	const LATER := 3
	var day := 1
	var reward := ""
	var state := LATER
	var _flash := 0.0
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(92, 104)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func flash() -> void:
		_flash = 1.0

	func _process(delta: float) -> void:
		_t += delta
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - delta * 1.6)
		if state == TODAY or _flash > 0.0:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var grand := day == 7
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2 if grand or state == TODAY else 1)
		match state:
			TAKEN:
				sb.bg_color = Color(0.2, 0.16, 0.08, 0.95)
				sb.border_color = UiTheme.GOLD
			TODAY:
				var pulse := 0.5 + 0.5 * sin(_t * 4.0)
				sb.bg_color = Color(0.36, 0.08, 0.06, 0.95).lerp(Color(0.5, 0.12, 0.08, 0.95), pulse)
				sb.border_color = Color(1, 0.8, 0.45).lerp(UiTheme.GOLD, pulse)
				sb.shadow_color = Color(0.9, 0.3, 0.1, 0.35 + 0.25 * pulse)
				sb.shadow_size = 8
			TOMORROW:
				sb.bg_color = Color(0.1, 0.09, 0.12, 0.95)
				sb.border_color = UiTheme.GOLD.darkened(0.3)
			_:
				sb.bg_color = Color(0.07, 0.065, 0.085, 0.95)
				sb.border_color = UiTheme.BRASS_DARK.lightened(0.3) if grand else UiTheme.BRASS_DARK
		if _flash > 0.0:
			sb.bg_color = sb.bg_color.lerp(Color(1, 0.85, 0.5), _flash * 0.6)
		draw_style_box(sb, r)
		var font := UiTheme.display_font()
		var dim := state == LATER or state == TOMORROW
		var col := UiTheme.MUTED if dim else UiTheme.TEXT
		_text(font, tr("DAY %d") % day, 14, 22.0, UiTheme.GOLD if state == TODAY else col)
		# a coin: brass disc with an inner ring
		var c := Vector2(size.x / 2.0, 50.0)
		var coin := UiTheme.GOLD if not dim else UiTheme.GOLD.darkened(0.45)
		draw_circle(c, 15.0 if grand else 12.0, coin)
		draw_arc(c, 9.0 if grand else 7.5, 0.0, TAU, 24, coin.darkened(0.35), 2.0, true)
		_text(font, reward, 13, 82.0, UiTheme.GOLD if not dim else UiTheme.MUTED)
		var tag := ""
		match state:
			TAKEN: tag = tr("TAKEN")
			TODAY: tag = tr("TODAY")
			TOMORROW: tag = tr("NEXT")
		if tag != "":
			_text(ThemeDB.fallback_font, tag, 11, 98.0, UiTheme.GREEN if state == TAKEN else UiTheme.MUTED)

	func _text(font: Font, s: String, fs: int, y: float, col: Color) -> void:
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) / 2.0, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A thin progress bar with "12 / 40" on its right.
class ProgressLine extends Control:
	var value := 0
	var goal := 1
	var done := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 16)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var label := "%d / %d" % [mini(value, goal), goal]
		var font := ThemeDB.fallback_font
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var w := size.x - lw - 12.0
		var y := size.y / 2.0
		draw_rect(Rect2(0, y - 4, w, 8), Color(0.06, 0.055, 0.07))
		draw_rect(Rect2(0, y - 4, w * clampf(float(value) / float(goal), 0.0, 1.0), 8), UiTheme.GREEN if done else UiTheme.ACCENT)
		draw_rect(Rect2(0, y - 4, w, 8), UiTheme.BRASS_DARK, false, 1.0)
		draw_string(font, Vector2(size.x - lw, y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.MUTED)


func _close() -> void:
	closed.emit()
	queue_free()
