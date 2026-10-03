class_name CardPanel
extends Control
## The result card (phase 25), opened from CHALLENGE FRIENDS at game over.
## The server draws the card from its own record of the game and answers with
## its address, a small PNG preview (this web engine has no JPEG decoder) and
## a message the bot prepared (the card, a caption and a Play button with the
## player's invite link). From here the player sends it to a chat, posts it
## as a story or saves it. Without cards (offline, an old Telegram) the plain
## invite text is shared as before.

signal closed

var _preview: TextureRect
var _status: Label
var _send: Button
var _story: Button
var _save: Button
var _card: Dictionary = {}
var _http: HTTPRequest
var _retried := false
var _wave := 0
var _kills := 0


func setup(wave: int, kills: int) -> CardPanel:
	_wave = wave
	_kills = kills
	return self


func _ready() -> void:
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)
	I18n.dir(row)

	# the card itself (4:5), a dark frame until it arrives
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.025, 0.03)
	sb.border_color = UiTheme.BRASS_DARK
	sb.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(frame)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(312, 390)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_preview)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(330, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(v)
	v.add_child(UiTheme.title(tr("YOUR RESULT CARD"), 26, UiTheme.GOLD))
	v.add_child(UiTheme.rule(320))
	_status = UiTheme.label(tr("Drawing your card…"), 17, UiTheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320, 0)
	v.add_child(_status)
	_send = UiTheme.big_button(tr("SEND TO A CHAT"), _on_send)
	_send.add_theme_font_size_override("font_size", 21)
	v.add_child(_send)
	_story = UiTheme.gold_button(tr("SHARE TO STORY"), _on_story)
	v.add_child(_story)
	_save = UiTheme.button(tr("SAVE IMAGE"), _on_save)
	v.add_child(_save)
	v.add_child(UiTheme.button(tr("CLOSE"), func():
		closed.emit()
		queue_free()))
	for b in [_send, _story, _save]:
		b.disabled = true

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_preview)
	Net.card_received.connect(_on_card)
	Net.request_card()
	print("[card] requested")


func _on_card(d: Dictionary) -> void:
	print("[card] status %d" % int(d.get("status", 4)))
	match int(d.get("status", 4)):
		0:
			_card = d
			_status.text = tr("Send it to your friends: they join your squad with one tap.")
			_send.disabled = false
			_story.disabled = not Platform.can_share_cards()
			_save.disabled = false
			if str(d.get("preview", "")) != "":
				_http.request(str(d.preview))
			print("[card] ready (prepared message: %s)" % ("yes" if str(d.get("prepared", "")) != "" else "no"))
		1:
			_status.text = tr("Survive a wave first, then your card is ready.")
			_fallback()
		2:
			_status.text = tr("Cards are not available on this server yet. You can still send your invite.")
			_fallback()
		3:
			_status.text = tr("One moment…")
			if not _retried:
				_retried = true
				get_tree().create_timer(8.5).timeout.connect(func():
					if is_inside_tree():
						Net.request_card())
		_:
			_status.text = tr("Could not draw the card. You can still send your invite.")
			_fallback()


## No card: the SEND button shares the invite text as before.
func _fallback() -> void:
	_send.disabled = false


func _on_preview(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("card preview: %d / %d" % [result, code])
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) == OK:
		_preview.texture = ImageTexture.create_from_image(img)


func _on_send() -> void:
	Platform.haptic("light")
	var prepared := str(_card.get("prepared", ""))
	if prepared != "" and Platform.share_message(prepared) == "ok":
		return
	# no prepared message (old Telegram, a browser): the invite text with the link
	var note := Social.challenge(_wave, _kills)
	if note != "":
		_status.text = note


func _on_story() -> void:
	if Platform.share_to_story(str(_card.get("url", "")), tr("Can you beat me? Play BLACK OFF in Telegram")) != "ok":
		_status.text = tr("Stories need a newer Telegram.")


func _on_save() -> void:
	if Platform.download_file(str(_card.get("url", "")), "blackoff-result.jpg") == "none":
		_status.text = tr("Could not save here.")
