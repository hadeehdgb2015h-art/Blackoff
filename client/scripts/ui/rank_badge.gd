class_name RankBadge
extends Control
## A rank's insignia (phase 26), drawn: chevrons, chevrons with rockers under
## them, bars, diamonds or a crown, in the tier's metal (iron, bronze, silver,
## gold, crimson gold). No stars or other symbols.

const METALS := {
	"iron": [Color(0.62, 0.62, 0.6), Color(0.32, 0.32, 0.32)],
	"bronze": [Color(0.85, 0.55, 0.3), Color(0.42, 0.24, 0.1)],
	"silver": [Color(0.9, 0.92, 0.95), Color(0.45, 0.48, 0.52)],
	"gold": [Color(1.0, 0.82, 0.38), Color(0.55, 0.36, 0.1)],
	"crimson": [Color(1.0, 0.45, 0.32), Color(0.55, 0.08, 0.06)],
}

var rank: Dictionary = {}


func _init(r: Dictionary = {}, side := 64.0) -> void:
	rank = r
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_rank(r: Dictionary) -> void:
	rank = r
	queue_redraw()


func _draw() -> void:
	draw_insignia(self, Rect2(Vector2.ZERO, size), rank)


## Draws `rank`'s insignia into `rect` of any canvas item (team list rows too).
static func draw_insignia(ci: CanvasItem, rect: Rect2, r: Dictionary) -> void:
	if r.is_empty():
		return
	var m: Array = METALS.get(str(r.get("metal", "iron")), METALS.iron)
	var hi: Color = m[0]
	var lo: Color = m[1]
	var n := clampi(int(r.get("count", 1)), 1, 3)
	var s := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	var w := s * 0.8
	match str(r.get("insignia", "chevron")):
		"chevron":
			_chevrons(ci, c + Vector2(0, -s * 0.06 * (n - 1)), w, s, n, hi, lo)
		"rocker":
			_chevrons(ci, c + Vector2(0, -s * 0.2), w * 0.92, s * 0.85, 3, hi, lo)
			for i in n:
				var y := c.y + s * 0.12 + i * s * 0.13
				_arc_band(ci, Vector2(c.x, y - s * 0.32), w * 0.46, s * 0.07, hi, lo)
		"bar":
			var bh := s * 0.14
			var gap := s * 0.08
			var total := n * bh + (n - 1) * gap
			for i in n:
				var y := c.y - total / 2.0 + i * (bh + gap)
				var br := Rect2(c.x - w * 0.42, y, w * 0.84, bh)
				ci.draw_rect(br, lo)
				ci.draw_rect(br.grow(-maxf(1.0, s * 0.025)), hi)
		"diamond":
			var d := s * (0.36 if n == 1 else 0.27 if n == 2 else 0.22)
			var step := d * 1.15
			for i in n:
				var x := c.x + (i - (n - 1) / 2.0) * step
				_diamond(ci, Vector2(x, c.y), d, hi, lo)
		"crown":
			var pts := PackedVector2Array([
				c + Vector2(-w * 0.45, s * 0.22), c + Vector2(-w * 0.45, -s * 0.12), c + Vector2(-w * 0.22, s * 0.04),
				c + Vector2(0, -s * 0.3), c + Vector2(w * 0.22, s * 0.04), c + Vector2(w * 0.45, -s * 0.12),
				c + Vector2(w * 0.45, s * 0.22)])
			ci.draw_colored_polygon(pts, lo)
			var inner := PackedVector2Array()
			for p in pts:
				inner.append(c + (p - c) * 0.84)
			ci.draw_colored_polygon(inner, hi)
			ci.draw_rect(Rect2(c.x - w * 0.45, c.y + s * 0.24, w * 0.9, s * 0.08), hi)


static func _chevrons(ci: CanvasItem, top: Vector2, w: float, s: float, n: int, hi: Color, lo: Color) -> void:
	var t := s * 0.11
	for i in n:
		var y := top.y + i * s * 0.17
		var a := Vector2(top.x - w / 2.0, y - s * 0.12)
		var b := Vector2(top.x, y + s * 0.08)
		var e := Vector2(top.x + w / 2.0, y - s * 0.12)
		var band := PackedVector2Array([a, b, e, e + Vector2(0, t), b + Vector2(0, t), a + Vector2(0, t)])
		ci.draw_colored_polygon(band, lo)
		var inset := t * 0.22
		ci.draw_colored_polygon(PackedVector2Array([a + Vector2(inset, inset), b + Vector2(0, inset), e + Vector2(-inset, inset),
			e + Vector2(-inset, t - inset), b + Vector2(0, t - inset), a + Vector2(inset, t - inset)]), hi)


static func _arc_band(ci: CanvasItem, center: Vector2, radius: float, t: float, hi: Color, lo: Color) -> void:
	ci.draw_arc(center, radius, deg_to_rad(30), deg_to_rad(150), 18, lo, t, true)
	ci.draw_arc(center, radius, deg_to_rad(32), deg_to_rad(148), 18, hi, t * 0.6, true)


static func _diamond(ci: CanvasItem, c: Vector2, d: float, hi: Color, lo: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d * 0.7, 0), c + Vector2(0, d), c + Vector2(-d * 0.7, 0)]), lo)
	var e := d * 0.78
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -e), c + Vector2(e * 0.7, 0), c + Vector2(0, e), c + Vector2(-e * 0.7, 0)]), hi)
