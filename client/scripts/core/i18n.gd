extends Node
## Autoload: the interface language (phase 24): English, Arabic or Russian.
##
## Every visible text goes through tr("English text"); res://data/i18n/<lang>.json
## maps the English text to the translation (tools/i18n.py checks that every
## tr() key and every data name has one, with the same placeholders).
##
## The translation is registered under the *English* locale on purpose: the
## engine mirrors every Control in a right-to-left locale, and a Control placed
## before it joins the tree keeps mirrored offsets (the HUD and menu broke on
## Arabic phones, phase 16). So the locale stays "en" and the layout stays
## left-to-right; panels opt into right-to-left with `I18n.dir(container)` in
## Arabic, and labels shape and order Arabic text on their own.
##
## The language is chosen in Settings (saved, also in localStorage so it
## survives the reload at once) and applied by reloading the page, so every
## text, cached or not, is built again in the new language. Default: the
## player's Telegram (or browser) language when it is one of ours, else English.

const LANGS := ["en", "ar", "ru"]
const NAMES := {"en": "English", "ar": "العربية", "ru": "Русский"}
const STORE_KEY := "blackoff.lang"
const FONT_AR_BODY := "res://assets/fonts/Cairo-Arabic.ttf"
const FONT_RU_BODY := "res://assets/fonts/Forum-Cyrillic.ttf"

var lang: String = "en"
var rtl: bool = false
var _translation: Translation


func _ready() -> void:
	_body_font()
	_apply(_pick())


## The language in force: ?lang= (screenshots), the saved choice, else the
## player's own language when we have it.
func _pick() -> String:
	var q := Platform.query_param("lang")
	if q in LANGS:
		return q
	var saved := Platform.stored_value(STORE_KEY)
	if saved == "":
		saved = Settings.language
	if saved in LANGS:
		return saved
	var own := Platform.user_language().substr(0, 2).to_lower()
	return own if own in LANGS else "en"


func _apply(code: String) -> void:
	if _translation:
		TranslationServer.remove_translation(_translation)
		_translation = null
	lang = code if code in LANGS else "en"
	rtl = lang == "ar"
	if lang != "en":
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/%s.json" % lang))
		if d is Dictionary:
			_translation = Translation.new()
			_translation.locale = "en"  # see the header: the layout must never mirror
			for k in d:
				if not str(k).begins_with("_") and str(d[k]) != "":
					_translation.add_message(str(k), str(d[k]))
			TranslationServer.add_translation(_translation)
		else:
			push_warning("I18n: data/i18n/%s.json missing or invalid; English it is" % lang)
	TranslationServer.set_locale("en")
	print("[i18n] language %s (%d strings)" % [lang, _translation.get_message_count() if _translation else 0])


## The body font (the engine's sans) learns Arabic and gets a Cyrillic fallback:
## every label, button and HUD text drawn with the default font can show them.
func _body_font() -> void:
	var fv := FontVariation.new()
	var base := ThemeDB.get_default_theme().default_font
	fv.base_font = base if base else ThemeDB.fallback_font
	var fallbacks: Array[Font] = []
	for path in [FONT_AR_BODY, FONT_RU_BODY]:
		var f := load(path) as Font
		if f:
			fallbacks.append(f)
	fv.fallbacks = fallbacks
	# the default theme carries its own font (it wins over the fallback font)
	ThemeDB.get_default_theme().default_font = fv
	ThemeDB.fallback_font = fv


## Saves the choice and reloads the page so the whole interface is rebuilt in it.
## Off the web (tests, desktop) the translation is swapped and the scene reloaded.
func set_language(code: String) -> void:
	if not code in LANGS:
		return
	Settings.language = code
	Settings.save()
	Platform.store_value(STORE_KEY, code)
	print("[i18n] switching to %s" % code)
	if Platform.is_web:
		# a moment for user:// to reach IndexedDB too
		await get_tree().create_timer(0.4).timeout
		Platform.reload_page()
	else:
		_apply(code)
		get_tree().reload_current_scene()


## Right-to-left for a panel's container in Arabic (rows reverse, text aligns right).
func dir(c: Control) -> Control:
	if rtl:
		c.layout_direction = Control.LAYOUT_DIRECTION_RTL
	return c


## A data name (weapon, perk, power-up, zombie) in the interface language.
func name_of(english: String) -> String:
	return tr(english)
