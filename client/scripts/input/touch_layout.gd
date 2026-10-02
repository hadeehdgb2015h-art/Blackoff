class_name TouchLayout
extends RefCounted
## HUD button layout: where each touch control sits and how big it is.
## Positions are normalised to the view (x/width, y/height) so a layout made on
## one phone fits another; `s` scales the button. Saved by Settings; edited by
## LayoutEditor. Pure functions, unit-tested.

const NAMES := ["stick", "fire", "fire2", "reload", "switch", "use", "pause", "mic", "speaker"]
const MIN_SCALE := 0.6
const MAX_SCALE := 1.7


## Default placement for a view of `size` (right-handed layout; a second
## fire button on the left is off by default).
static func defaults(size: Vector2) -> Dictionary:
	var d := {
		"stick": _n(size, Vector2(175, size.y - 165), 1.0),
		"fire": _n(size, Vector2(size.x - 155, size.y - 165), 1.0),
		"fire2": _n(size, Vector2(330, size.y - 300), 1.0),
		"reload": _n(size, Vector2(size.x - 300, size.y - 85), 1.0),
		"switch": _n(size, Vector2(size.x - 95, size.y - 320), 1.0),
		"use": _n(size, Vector2(size.x - 300, size.y - 230), 1.0),
		"pause": _n(size, Vector2(size.x - 46, 46), 1.0),
		"mic": _n(size, Vector2(size.x - 46, 118), 1.0),
		"speaker": _n(size, Vector2(size.x - 46, 182), 1.0),
	}
	d["fire2"]["enabled"] = false
	return d


static func _n(size: Vector2, px: Vector2, s: float) -> Dictionary:
	return {"x": px.x / size.x, "y": px.y / size.y, "s": s}


## Layout `saved` (possibly partial or from an older version) completed with
## defaults and clamped to sane values.
static func resolve(saved: Dictionary, size: Vector2) -> Dictionary:
	var out := defaults(size)
	for name in NAMES:
		var e: Variant = saved.get(name)
		if e is Dictionary:
			out[name]["x"] = clampf(float(e.get("x", out[name].x)), 0.03, 0.97)
			out[name]["y"] = clampf(float(e.get("y", out[name].y)), 0.05, 0.95)
			out[name]["s"] = clampf(float(e.get("s", 1.0)), MIN_SCALE, MAX_SCALE)
			if name == "fire2":
				out[name]["enabled"] = bool(e.get("enabled", false))
	return out


static func position(layout: Dictionary, name: String, size: Vector2) -> Vector2:
	var e: Dictionary = layout[name]
	return Vector2(float(e.x) * size.x, float(e.y) * size.y)


static func scale(layout: Dictionary, name: String) -> float:
	return float(layout[name].get("s", 1.0))


## Moves a control to pixel position `px`, keeping it inside the view.
static func place(layout: Dictionary, name: String, px: Vector2, size: Vector2) -> void:
	layout[name]["x"] = clampf(px.x / size.x, 0.03, 0.97)
	layout[name]["y"] = clampf(px.y / size.y, 0.05, 0.95)
