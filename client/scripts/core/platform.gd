extends Node
## Platform facade: Web/Telegram detection and Telegram WebApp calls.
## All Telegram access goes through here so gameplay code never touches
## JavaScriptBridge directly. On non-web platforms every call is a safe no-op.

var is_web: bool = false
var is_telegram: bool = false
var is_touch: bool = false
var telegram_platform: String = ""
var telegram_version: String = ""

## Back (phase 27): every open panel registers how it closes. Telegram's back
## button (shown while something is open; the phone's back key presses it, so
## a player no longer leaves the game by mistake) and Escape close the newest
## one. In a game the bottom entry opens the pause menu.
var _backs: Array[Dictionary] = []
var _back_shown := false
var _back_poll := 0.0


func _ready() -> void:
	# The engine mirrors every Control in right-to-left locales (an Arabic phone):
	# money on the left, the menu flipped, and controls positioned before they
	# join the tree stored mirrored. The interface is English and laid out
	# left-to-right: use an English locale for layout. Arabic text inside labels
	# is still shaped and ordered right-to-left by the text server, and the
	# translations (I18n, phase 24) are registered under this English locale.
	TranslationServer.set_locale("en")
	get_tree().root.set_layout_direction(Window.LAYOUT_DIRECTION_LTR)
	is_web = OS.has_feature("web")
	is_touch = DisplayServer.is_touchscreen_available()
	if is_web:
		is_telegram = bool(_js("window.BlackoffTG ? window.BlackoffTG.isTelegram() : false"))
		if is_telegram:
			telegram_platform = str(_js("window.Telegram.WebApp.platform"))
			telegram_version = str(_js("window.Telegram.WebApp.version"))


## Registers how `node` closes; forgotten once the node is freed.
func on_back(node: Node, close: Callable) -> void:
	_backs.append({"node": node, "close": close})


## Closes the newest open panel; false when nothing is open.
func go_back() -> bool:
	var top := _top_back()
	if top.is_empty():
		return false
	print("[back] %s" % top.node.name)
	top.close.call()
	return true


func _top_back() -> Dictionary:
	for i in range(_backs.size() - 1, -1, -1):
		var b: Dictionary = _backs[i]
		if not is_instance_valid(b.node) or b.node.is_queued_for_deletion():
			_backs.remove_at(i)
			continue
		var n: Node = b.node
		if not n.is_inside_tree() or (n is CanvasItem and not (n as CanvasItem).is_visible_in_tree()):
			continue
		return b
	return {}


func _process(delta: float) -> void:
	_back_poll += delta
	if _back_poll < 0.1:
		return
	_back_poll = 0.0
	var show := not _top_back().is_empty()
	if not is_web:  # browsers too (no button there): tests press it with BlackoffTG._backPresses
		return
	if show != _back_shown:
		_back_shown = show
		_js("window.BlackoffTG.setBack(%s)" % ("true" if show else "false"))
	if int(_js("window.BlackoffTG.takeBack()")) > 0:
		go_back()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if go_back():
			get_viewport().set_input_as_handled()


## Raw Telegram initData string. Sent to the server for HMAC validation;
## never trusted or parsed for identity on the client.
func get_init_data() -> String:
	if not is_telegram:
		return ""
	return str(_js("window.Telegram.WebApp.initData || ''"))


## URL query parameter, e.g. ?bot=1. Outside the browser the environment
## variable BLACKOFF_<KEY> is used instead (headless smoke runs).
func query_param(key: String) -> String:
	if not is_web:
		return OS.get_environment("BLACKOFF_" + key.to_upper())
	var v: Variant = _js("new URLSearchParams(window.location.search).get('%s') || ''" % key.replace("'", ""))
	return str(v) if v != null else ""


## Build id injected by tools/export_web.sh (web only), shown in the menu.
func build_id() -> String:
	if not is_web:
		return "dev"
	var v: Variant = _js("window.BLACKOFF_BUILD || ''")
	return str(v) if v != null else ""


## Value from the optional config.js next to index.html (written by the
## server installer, e.g. the game server URL). Empty when absent.
func web_config(key: String) -> String:
	if not is_web:
		return ""
	var v: Variant = _js("(window.BLACKOFF_CONFIG && window.BLACKOFF_CONFIG['%s']) || ''" % key.replace("'", ""))
	return str(v) if v != null else ""


# ---- Voice chat (web/voice.js). Off the web every call is a no-op.

## True when the page can capture and play audio (not in every Telegram version).
func voice_supported() -> bool:
	if not is_web:
		return false
	return bool(_js("!!(window.BlackoffVoice && window.BlackoffVoice.supported())"))


func voice_configure(c: Dictionary) -> void:
	if is_web:
		_js("window.BlackoffVoice && window.BlackoffVoice.configure(%s)" % JSON.stringify(c))


func voice_set_mic(on: bool) -> void:
	if is_web:
		_js("window.BlackoffVoice && window.BlackoffVoice.setMic(%s)" % ("true" if on else "false"))


func voice_set_speaker(on: bool) -> void:
	if is_web:
		_js("window.BlackoffVoice && window.BlackoffVoice.setSpeaker(%s)" % ("true" if on else "false"))


## Next encoded microphone frame, or an empty array.
func voice_take() -> PackedByteArray:
	if not is_web:
		return PackedByteArray()
	var v: Variant = _js("window.BlackoffVoice ? window.BlackoffVoice.take() : null")
	return v if v is PackedByteArray else PackedByteArray()


## Plays a frame from another player.
func voice_play(entity_id: int, seq: int, data: PackedByteArray) -> void:
	if is_web:
		_js("window.BlackoffVoice && window.BlackoffVoice.play(%d, %d, '%s')" % [entity_id, seq, Marshalls.raw_to_base64(data)])


## {mic: off|starting|on|denied|unsupported, speaker: on|off, talking: bool, sent, received, played}
func voice_status() -> Dictionary:
	if not is_web:
		return {}
	var v: Variant = _js("window.BlackoffVoice ? window.BlackoffVoice.status() : ''")
	var d: Variant = JSON.parse_string(str(v)) if v != null and str(v) != "" else null
	return d if d is Dictionary else {}


## Entity ids heard in the last moment.
func voice_speaking() -> Array:
	if not is_web:
		return []
	var v: Variant = _js("window.BlackoffVoice ? window.BlackoffVoice.speaking() : '[]'")
	var d: Variant = JSON.parse_string(str(v)) if v != null else null
	var out: Array = []
	if d is Array:
		for x in d:
			out.append(int(x))
	return out


## Screen edges covered by the host (Telegram's close/menu buttons, cut-outs,
## gesture bars), in the game's virtual pixels: {top, right, bottom, left}.
## Zero outside Telegram. The menu, HUD and touch layout keep clear of them.
func safe_insets(view_size: Vector2) -> Dictionary:
	var z := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
	if not is_telegram:
		return z
	var v: Variant = _js("JSON.stringify(window.BlackoffTG.safeArea())")
	var d: Variant = JSON.parse_string(str(v)) if v != null else null
	# the canvas's own height in CSS px (the page turns it on an upright phone)
	var h: Variant = _js("(window.BlackoffRotate && window.BlackoffRotate.state.rotated) ? window.innerWidth : window.innerHeight")
	if not (d is Dictionary) or h == null or float(h) <= 0.0:
		return z
	var k := view_size.y / float(h)  # CSS px -> virtual px (canvas_items stretch keeps the base height)
	for key in z:
		z[key] = clampf(float(d.get(key, 0.0)) * k, 0.0, view_size.y * 0.25)
	return z


func request_fullscreen() -> void:
	if is_web:
		_js("window.BlackoffTG && window.BlackoffTG.enterFullscreen()")


## The invite parameter of a t.me/<bot>?startapp=... link ("" when none).
## Also ?startapp= in a plain browser (tests).
func start_param() -> String:
	if not is_web:
		return OS.get_environment("BLACKOFF_STARTAPP")
	var v: Variant = _js("window.BlackoffTG ? window.BlackoffTG.startParam() : ''")
	return str(v) if v != null else ""


## Opens a share sheet for a link with a message: Telegram's chat picker in the
## Mini App. Returns "telegram", "system", "copied" or "none".
func share(url: String, text: String) -> String:
	if not is_web:
		return "none"
	var v: Variant = _js("window.BlackoffTG ? window.BlackoffTG.share(%s, %s) : 'none'" % [JSON.stringify(url), JSON.stringify(text)])
	return str(v) if v != null else "none"


## The player's language: Telegram's user language inside Telegram, else the
## browser's (e.g. "ar", "ru-RU"); "" when unknown (phase 24).
func user_language() -> String:
	if not is_web:
		return OS.get_locale_language()
	var v: Variant = _js("(window.Telegram && window.Telegram.WebApp && window.Telegram.WebApp.initDataUnsafe && window.Telegram.WebApp.initDataUnsafe.user && window.Telegram.WebApp.initDataUnsafe.user.language_code) || navigator.language || ''")
	return str(v) if v != null else ""


## A small value kept in the browser's localStorage, written at once (unlike
## user://, which reaches IndexedDB a moment later): survives a page reload.
func store_value(key: String, value: String) -> void:
	if is_web:
		_js("try { localStorage.setItem(%s, %s) } catch (e) {}" % [JSON.stringify(key), JSON.stringify(value)])


func stored_value(key: String) -> String:
	if not is_web:
		return ""
	var v: Variant = _js("(function () { try { return localStorage.getItem(%s) || '' } catch (e) { return '' } })()" % JSON.stringify(key))
	return str(v) if v != null else ""


## Even frame pacing in the page (phase 30); false when the page cannot (the
## engine's own cap is used then).
func set_frame_cap(fps: int) -> bool:
	if not is_web:
		return false
	return bool(_js("window.BlackoffPace ? (window.BlackoffPace.setCap(%d), true) : false" % fps))


## The display's refresh rate in Hz (0 when unknown), for problem reports.
func display_hz() -> int:
	if not is_web:
		return 0
	var v: Variant = _js("window.BlackoffPace ? window.BlackoffPace.info().hz : 0")
	return int(v) if v != null else 0


## The screen in device pixels, e.g. 1080x2400 (problem reports).
func screen_desc() -> String:
	if is_web:
		var v: Variant = _js("Math.round(screen.width * (window.devicePixelRatio || 1)) + 'x' + Math.round(screen.height * (window.devicePixelRatio || 1))")
		return str(v) if v != null else ""
	var s := DisplayServer.screen_get_size()
	return "%dx%d" % [s.x, s.y]


## Opens a t.me link (inside Telegram: without leaving it; elsewhere a new tab).
func open_telegram_link(url: String) -> void:
	if not is_web:
		OS.shell_open(url)
		return
	_js("(function (u) { var w = window.Telegram && window.Telegram.WebApp; if (w && w.initData && w.openTelegramLink) w.openTelegramLink(u); else window.open(u, '_blank'); })(%s)" % JSON.stringify(url))


## Reloads the page (the language changed: every text is built again).
func reload_page() -> void:
	if is_web:
		_js("window.location.reload()")


## Result cards (phase 25): send the bot's prepared message (photo + Play
## button) to a chat the player picks; "ok" or "unsupported".
func share_message(prepared_id: String) -> String:
	if not is_web:
		return "unsupported"
	var v: Variant = _js("window.BlackoffTG ? window.BlackoffTG.shareMessage(%s) : 'unsupported'" % JSON.stringify(prepared_id))
	return str(v) if v != null else "unsupported"


func share_to_story(url: String, text: String) -> String:
	if not is_web:
		return "unsupported"
	var v: Variant = _js("window.BlackoffTG ? window.BlackoffTG.shareToStory(%s, %s) : 'unsupported'" % [JSON.stringify(url), JSON.stringify(text)])
	return str(v) if v != null else "unsupported"


func download_file(url: String, file_name: String) -> String:
	if not is_web:
		return "none"
	var v: Variant = _js("window.BlackoffTG ? window.BlackoffTG.downloadFile(%s, %s) : 'none'" % [JSON.stringify(url), JSON.stringify(file_name)])
	return str(v) if v != null else "none"


## Telegram can send, story-share and save cards (inside Telegram 7.8+).
func can_share_cards() -> bool:
	return is_web and bool(_js("window.BlackoffTG ? window.BlackoffTG.canShareCards() : false"))


func haptic(kind: String = "light") -> void:
	if is_telegram:
		_js("window.BlackoffTG.haptic('%s')" % kind.replace("'", ""))


func _js(code: String) -> Variant:
	if not is_web:
		return null
	return JavaScriptBridge.eval(code, true)
