class_name UiTheme
extends RefCounted
## Shared UI look (phase 14): dark fantasy. Near-black stone panels with an
## old-brass edge, ember red for danger and calls to action, bone-white text,
## Cinzel (OFL, assets/fonts) for titles and buttons. Button faces are small
## generated gradient textures (9-slice), so every control shares one style
## without art files. No stars, sigils or symbols anywhere: lines and diamonds only.

const ACCENT := Color(0.78, 0.19, 0.16)      ## ember red
const ACCENT_DARK := Color(0.42, 0.08, 0.07)
const TEXT := Color(0.91, 0.88, 0.8)         ## bone
const MUTED := Color(0.58, 0.56, 0.52)
const GOLD := Color(0.85, 0.7, 0.36)         ## old brass
const BRASS_DARK := Color(0.42, 0.33, 0.17)
const GREEN := Color(0.45, 0.85, 0.5)
const BG := Color(0.035, 0.035, 0.05)
const STONE := Color(0.13, 0.12, 0.15)
const STONE_DARK := Color(0.07, 0.065, 0.085)

const FONT_DISPLAY := "res://assets/fonts/Cinzel.ttf"

static var _theme: Theme
static var _display: Font
static var _tex_cache := {}


## The display font (titles, buttons); the engine's default sans for body text.
static func display_font() -> Font:
	if _display == null:
		if ResourceLoader.exists(FONT_DISPLAY):
			# Cinzel has Latin only: player names in Arabic and other scripts fall
			# back to the engine font instead of showing boxes
			var fv := FontVariation.new()
			fv.base_font = load(FONT_DISPLAY)
			fv.fallbacks = [ThemeDB.fallback_font]
			_display = fv
		else:
			_display = ThemeDB.fallback_font
	return _display


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	# panels: dark stone with a brass edge
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	# buttons
	t.set_stylebox("normal", "Button", button_box(STONE, STONE_DARK, BRASS_DARK))
	t.set_stylebox("hover", "Button", button_box(STONE.lightened(0.08), STONE_DARK.lightened(0.05), GOLD))
	t.set_stylebox("pressed", "Button", button_box(ACCENT_DARK.lightened(0.1), ACCENT_DARK, GOLD))
	t.set_stylebox("disabled", "Button", button_box(Color(0.09, 0.09, 0.1), Color(0.06, 0.06, 0.07), Color(0.2, 0.19, 0.17)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", display_font())
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.97, 0.9))
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.85))
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.4, 0.38))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.7))
	t.set_constant("outline_size", "Button", 3)
	# check buttons and sliders inherit the button face
	t.set_font("font", "CheckButton", display_font())
	t.set_font_size("font_size", "CheckButton", 18)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.03, 0.03, 0.04, 0.9)
	track.border_color = BRASS_DARK
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(3)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", knob_texture())
	t.set_icon("grabber_highlight", "HSlider", knob_texture())
	# labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	_theme = t
	return t


# ------------------------------------------------------------------ generated styles

## Dark stone panel: gradient face, brass edge, soft inner shadow at the top.
static func panel_box(margin := 24) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _face_texture("panel", Color(0.09, 0.085, 0.11, 0.96), Color(0.045, 0.04, 0.06, 0.97), BRASS_DARK, 1, 0.35)
	sb.texture_margin_left = 8
	sb.texture_margin_right = 8
	sb.texture_margin_top = 8
	sb.texture_margin_bottom = 8
	sb.set_content_margin_all(margin)
	return sb


static func button_box(top: Color, bottom: Color, border: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _face_texture("btn_%s_%s_%s" % [top.to_html(), bottom.to_html(), border.to_html()], top, bottom, border, 1, 0.5)
	sb.texture_margin_left = 8
	sb.texture_margin_right = 8
	sb.texture_margin_top = 8
	sb.texture_margin_bottom = 8
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


## A 48x48 face: vertical gradient, 1 px border, a lighter bevel line under the
## top edge and a darker one above the bottom. Cached by key.
static func _face_texture(key: String, top: Color, bottom: Color, border: Color, border_w: int, bevel: float) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := 48
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var k := float(y) / float(n - 1)
		var c := top.lerp(bottom, k)
		for x in n:
			img.set_pixel(x, y, c)
	var hi := top.lightened(bevel * 0.5)
	hi.a = top.a
	var lo := bottom.darkened(0.5)
	lo.a = bottom.a
	for x in n:
		img.set_pixel(x, border_w, hi)
		img.set_pixel(x, n - 1 - border_w, lo)
	for i in border_w:
		for x in n:
			img.set_pixel(x, i, border)
			img.set_pixel(x, n - 1 - i, border)
		for y in n:
			img.set_pixel(i, y, border)
			img.set_pixel(n - 1 - i, y, border)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func knob_texture() -> ImageTexture:
	if _tex_cache.has("knob"):
		return _tex_cache["knob"]
	var n := 22
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n / 2.0 - 0.5, n / 2.0 - 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d <= n / 2.0 - 1.0:
				col = GOLD if d > n / 2.0 - 3.5 else Color(0.16, 0.14, 0.12)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["knob"] = tex
	return tex


# ------------------------------------------------------------------ widgets

static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A title in the display font.
static func title(text: String, size := 32, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", display_font())
	return l


## Spaced capitals ("D A R K   F A N T A S Y"): the cheap way to look engraved.
static func spaced(text: String) -> String:
	var out := PackedStringArray()
	for ch in text.to_upper():
		out.append("  " if ch == " " else ch)
	return " ".join(out)


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		var tree := Engine.get_main_loop() as SceneTree
		var audio: Node = tree.root.get_node_or_null("Audio") if tree else null
		if audio:
			audio.ui_click()
		cb.call())
	b.focus_mode = Control.FOCUS_NONE
	return b


## The ember call to action (play buttons).
static func big_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_stylebox_override("normal", button_box(Color(0.6, 0.14, 0.11), Color(0.3, 0.06, 0.05), GOLD))
	b.add_theme_stylebox_override("hover", button_box(Color(0.68, 0.17, 0.13), Color(0.34, 0.07, 0.06), Color(1, 0.86, 0.5)))
	b.add_theme_stylebox_override("pressed", button_box(Color(0.78, 0.22, 0.16), Color(0.4, 0.09, 0.07), Color(1, 0.9, 0.6)))
	b.add_theme_stylebox_override("disabled", button_box(Color(0.18, 0.1, 0.1), Color(0.1, 0.06, 0.06), Color(0.3, 0.26, 0.2)))
	var sb: StyleBoxTexture = b.get_theme_stylebox("normal")
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return b


## A gold-edged secondary button (leaderboard, confirmations).
static func gold_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb)
	b.add_theme_stylebox_override("normal", button_box(Color(0.2, 0.17, 0.12), Color(0.1, 0.085, 0.06), GOLD))
	b.add_theme_stylebox_override("hover", button_box(Color(0.26, 0.22, 0.14), Color(0.13, 0.11, 0.07), Color(1, 0.86, 0.5)))
	b.add_theme_stylebox_override("pressed", button_box(Color(0.32, 0.26, 0.16), Color(0.16, 0.13, 0.08), Color(1, 0.9, 0.6)))
	b.add_theme_color_override("font_color", GOLD)
	return b


## Ornamental rule: a thin brass line with a diamond at the centre.
static func rule(width := 400.0, color := GOLD) -> Control:
	var r := Rule.new()
	r.custom_minimum_size = Vector2(width, 14)
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


class Rule extends Control:
	var color := Color(0.85, 0.7, 0.36)

	func _draw() -> void:
		var y := size.y / 2.0
		var mid := size.x / 2.0
		var faint := Color(color.r, color.g, color.b, 0.35)
		draw_line(Vector2(0, y), Vector2(mid - 14, y), faint, 1.0, true)
		draw_line(Vector2(mid + 14, y), Vector2(size.x, y), faint, 1.0, true)
		var d := 5.0
		draw_colored_polygon(PackedVector2Array([Vector2(mid, y - d), Vector2(mid + d, y), Vector2(mid, y + d), Vector2(mid - d, y)]), color)
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 10, y - 2), Vector2(mid - 8, y), Vector2(mid - 10, y + 2), Vector2(mid - 12, y)]), faint)
		draw_colored_polygon(PackedVector2Array([Vector2(mid + 10, y - 2), Vector2(mid + 12, y), Vector2(mid + 10, y + 2), Vector2(mid + 8, y)]), faint)


## Full-screen vignette (dark edges) over a backdrop.
static func vignette(strength := 0.85) -> TextureRect:
	var tr := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0, 0, 0, strength * 0.25))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, strength))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	tr.texture = gt
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Slow embers drifting up (menu and pause backdrops). Cheap: 2D particles.
static func embers(amount := 36) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 7.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(700, 40)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -12)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 45.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.55, 0.2, 0.0))
	g.add_point(0.2, Color(1.0, 0.5, 0.15, 0.9))
	g.add_point(0.7, Color(0.9, 0.25, 0.1, 0.5))
	g.set_color(g.get_point_count() - 1, Color(0.4, 0.05, 0.02, 0.0))
	p.color_ramp = g
	return p
