class_name UiTheme
extends RefCounted
## Shared UI look: dark translucent panels, emergency-red accent.

const ACCENT := Color(0.78, 0.19, 0.16)
const TEXT := Color(0.92, 0.93, 0.9)
const MUTED := Color(0.6, 0.63, 0.66)
const GOLD := Color(0.95, 0.78, 0.3)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.06, 0.07, 0.92)
	panel.border_color = Color(0.25, 0.27, 0.3)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(14)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		match state:
			"normal":
				sb.bg_color = Color(0.13, 0.14, 0.16)
			"hover":
				sb.bg_color = Color(0.2, 0.21, 0.24)
			"pressed":
				sb.bg_color = ACCENT
			"disabled":
				sb.bg_color = Color(0.09, 0.09, 0.1)
			"focus":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = ACCENT
				sb.set_border_width_all(2)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.42))
	t.set_font_size("font_size", "Button", 26)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 5)
	_theme = t
	return t


static func label(text: String, size := 24, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b
