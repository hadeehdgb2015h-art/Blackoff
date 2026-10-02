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
