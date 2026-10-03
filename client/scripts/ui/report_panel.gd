class_name ReportPanel
extends Control
## REPORT A PROBLEM (phase 29), from the settings and the pause menu. The
## player picks what went wrong; the game adds a screenshot (taken before this
## panel opened, without the menus over it) and its own settings, and the
## server sends it all to the developer through the bot. Details are written
## in the bot's chat afterwards, where typing is native.

const MAX_SHOT_BYTES := 44000

var where := "menu"
var _shot := PackedByteArray()
var _shot_tex: ImageTexture
var _category := -1
var _cats: Array[Button] = []
var _attach: CheckButton
var _status: Label
var _send: Button
var _close: Button
var _write: Button
var _fps := 0.0


## Takes a screenshot with `hide` hidden, then opens the panel on `host`.
static func open(host: Node, hide: Array, where_text: String) -> void:
	var fps := Engine.get_frames_per_second()
	var was := []
	for n in hide:
		if is_instance_valid(n) and n is CanvasItem:
			was.append([n, n.visible])
			n.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = host.get_viewport().get_texture().get_image()
	for p in was:
		if is_instance_valid(p[0]):
			p[0].visible = p[1]
	if not is_instance_valid(host):
		return
	var panel := ReportPanel.new()
	panel.where = where_text
	panel._fps = fps
	panel._encode(img)
	host.add_child(panel)


## A small WebP of the frame (640 px wide, smaller if needed to fit the limit).
func _encode(img: Image) -> void:
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGB8)
	for w in [640, 480, 360]:
		var shot := img.duplicate() as Image
		shot.resize(w, maxi(1, roundi(img.get_height() * w / float(img.get_width()))), Image.INTERPOLATE_BILINEAR)
		for q in [0.55, 0.35]:
			var bytes := shot.save_webp_to_buffer(true, q)
			if bytes.size() > 0 and bytes.size() <= MAX_SHOT_BYTES:
				_shot = bytes
				_shot_tex = ImageTexture.create_from_image(shot)
				print("[report] screenshot %dx%d, %d bytes" % [shot.get_width(), shot.get_height(), bytes.size()])
				return


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(20))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(640, 0)
	panel.add_child(v)
	I18n.dir(v)
	v.add_child(UiTheme.title(tr("REPORT A PROBLEM"), 28, UiTheme.GOLD))
	v.add_child(UiTheme.rule(600))
	v.add_child(UiTheme.label(tr("What went wrong?"), 18, UiTheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	I18n.dir(grid)
	var group := ButtonGroup.new()
	# in the order of the protocol's reportCategory
	var names := [tr("Lag or stutter"), tr("Controls or aim"), tr("Connection"), tr("Sound"), tr("Something looks wrong"), tr("Something else")]
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(204, 52)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func():
			_category = i
			_send.disabled = false)
		grid.add_child(b)
		_cats.append(b)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	I18n.dir(row)
	if _shot_tex:
		var frame := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.025, 0.03)
		sb.border_color = UiTheme.BRASS_DARK
		sb.set_border_width_all(1)
		frame.add_theme_stylebox_override("panel", sb)
		var pic := TextureRect.new()
		pic.texture = _shot_tex
		pic.custom_minimum_size = Vector2(176, 84)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(pic)
		row.add_child(frame)
	_attach = CheckButton.new()
	_attach.text = tr("Attach a screenshot of the game")
	_attach.button_pressed = not _shot.is_empty()
	_attach.disabled = _shot.is_empty()
	_attach.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_attach)

	_status = UiTheme.label(tr("The game adds your device and settings, so the developer can find the problem."), 15, UiTheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(600, 0)
	v.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(buttons)
	I18n.dir(buttons)
	_send = UiTheme.gold_button(tr("SEND"), _on_send)
	_send.disabled = true
	buttons.add_child(_send)
	_write = UiTheme.button(tr("WRITE TO THE BOT"), _on_write)
	_write.visible = false
	buttons.add_child(_write)
	_close = UiTheme.button(tr("CANCEL"), _on_close)
	buttons.add_child(_close)
	Platform.on_back(self, _on_close)
	Net.reported.connect(_on_reported)
	if not Net.can_report():
		_status.text = tr("No connection to the server: reports can be sent once the game is online.")
	print("[report] panel opened (%s)" % where)


func _details() -> Dictionary:
	return {
		"quality": Settings.effective_quality(), "fpsCap": Settings.fps_cap, "tpp": Settings.third_person,
		"sens": snappedf(Settings.sensitivity, 0.01), "ping": roundi(Net.rtt_ms), "net": Net.status, "hz": Platform.display_hz(),
		"voice": Net.voice_mic, "touch": Platform.is_touch,
	}


func _on_send() -> void:
	if _category < 0:
		return
	Platform.haptic("light")
	_send.disabled = true
	for b in _cats:
		b.disabled = true
	_attach.disabled = true
	_status.text = tr("Sending…")
	Net.send_report(_category, where, _fps, _details(), _shot if _attach.button_pressed else PackedByteArray())


func _on_reported(status: int, id: int) -> void:
	match status:
		0:
			_status.text = tr("Report #%d sent. Thank you!\nTo add details, write to the bot: they go straight to the developer.") % id
			_status.add_theme_color_override("font_color", UiTheme.GOLD)
			_send.visible = false
			_write.visible = Net.bot_username != "" and Platform.is_telegram
			_close.text = tr("CLOSE")
			print("[report] sent as #%d" % id)
		1:
			_status.text = tr("You just sent a report. Wait a minute before the next one.")
			_unlock()
		_:
			_status.text = tr("Could not send the report. Check the connection and try again.")
			_unlock()


func _unlock() -> void:
	_send.disabled = _category < 0
	for b in _cats:
		b.disabled = false
	_attach.disabled = _shot.is_empty()


func _on_write() -> void:
	Platform.open_telegram_link("https://t.me/" + Net.bot_username)


func _on_close() -> void:
	queue_free()
