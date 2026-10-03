class_name ScopeOverlay
extends Control
## The sniper scope (phase 22): black outside a round lens with a soft rim,
## fine cross hairs thickening towards the edge, range marks and a small red
## centre dot. Drawn when the rig is scoped in; one texture made once.

static var _lens: ImageTexture

var _alpha: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if _lens == null:
		_lens = _make_lens()


## `on` while scoped; fades in quickly.
func set_scoped(on: bool, delta: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if on else 0.0, delta / 0.08)
	visible = _alpha > 0.01
	modulate.a = _alpha
	if visible:
		queue_redraw()


func _draw() -> void:
	var s := size
	var d := minf(s.x, s.y) * 0.96
	var r := Rect2((s - Vector2(d, d)) / 2.0, Vector2(d, d))
	var black := Color(0, 0, 0, 1)
	# outside the lens square
	draw_rect(Rect2(0, 0, r.position.x + 1, s.y), black)
	draw_rect(Rect2(r.end.x - 1, 0, s.x - r.end.x + 1, s.y), black)
	draw_rect(Rect2(0, 0, s.x, r.position.y + 1), black)
	draw_rect(Rect2(0, r.end.y - 1, s.x, s.y - r.end.y + 1), black)
	draw_texture_rect(_lens, r, false)
	var c := s / 2.0
	var rad := d * 0.47
	var ink := Color(0.02, 0.02, 0.03, 0.95)
	# fine near the centre, thick posts towards the rim
	draw_line(c - Vector2(rad, 0), c - Vector2(rad * 0.35, 0), ink, 4.0)
	draw_line(c + Vector2(rad * 0.35, 0), c + Vector2(rad, 0), ink, 4.0)
	draw_line(c + Vector2(0, rad * 0.35), c + Vector2(0, rad), ink, 4.0)
	draw_line(c - Vector2(rad * 0.35, 0), c + Vector2(rad * 0.35, 0), ink, 1.4)
	draw_line(c - Vector2(0, rad * 0.35), c + Vector2(0, rad * 0.35), ink, 1.4)
	draw_line(c - Vector2(0, rad), c - Vector2(0, rad * 0.35), ink, 1.4)
	for i in range(1, 5):
		var o := rad * 0.075 * i
		draw_line(c + Vector2(o, -4), c + Vector2(o, 4), ink, 1.2)
		draw_line(c - Vector2(o, 4), c - Vector2(o, -4), ink, 1.2)
		draw_line(c + Vector2(-4, o), c + Vector2(4, o), ink, 1.2)
	draw_circle(c, 2.6, Color(0, 0, 0, 0.8))
	draw_circle(c, 1.7, Color(1.0, 0.18, 0.12, 0.95))


## Transparent lens with a dark soft rim, black corners.
static func _make_lens() -> ImageTexture:
	var n := 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n / 2.0 - 0.5, n / 2.0 - 0.5)
	for y in n:
		for x in n:
			var r := Vector2(x, y).distance_to(c) / (n / 2.0)
			var a := smoothstep(0.9, 0.985, r)  # rim shadow, then solid black
			var tint := 0.06 * (1.0 - a) * smoothstep(0.4, 0.9, r)  # a faint vignette inside the glass
			img.set_pixel(x, y, Color(0, 0, 0, clampf(a + tint, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
