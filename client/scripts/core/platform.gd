extends Node
## Platform facade: Web/Telegram detection and Telegram WebApp calls.
## All Telegram access goes through here so gameplay code never touches
## JavaScriptBridge directly. On non-web platforms every call is a safe no-op.

var is_web: bool = false
var is_telegram: bool = false
var is_touch: bool = false
var telegram_platform: String = ""
var telegram_version: String = ""


func _ready() -> void:
	# The engine mirrors every Control in right-to-left locales (an Arabic phone):
	# money on the left, the menu flipped, and controls positioned before they
	# join the tree stored mirrored. The interface is English and laid out
	# left-to-right: use an English locale for layout. Arabic text inside labels
	# (player names) is still shaped and ordered right-to-left by the text server.
	TranslationServer.set_locale("en")
	get_tree().root.set_layout_direction(Window.LAYOUT_DIRECTION_LTR)
	is_web = OS.has_feature("web")
	is_touch = DisplayServer.is_touchscreen_available()
	if is_web:
		is_telegram = bool(_js("window.BlackoffTG ? window.BlackoffTG.isTelegram() : false"))
		if is_telegram:
			telegram_platform = str(_js("window.Telegram.WebApp.platform"))
			telegram_version = str(_js("window.Telegram.WebApp.version"))


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


func haptic(kind: String = "light") -> void:
	if is_telegram:
		_js("window.BlackoffTG.haptic('%s')" % kind.replace("'", ""))


func _js(code: String) -> Variant:
	if not is_web:
		return null
	return JavaScriptBridge.eval(code, true)
