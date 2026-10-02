extends TestCase
## Touch control layout: defaults, saving, clamping and resolution of old data.


func test_defaults_and_resolve() -> void:
	var size := Vector2(1280, 720)
	var d := TouchLayout.defaults(size)
	for name in TouchLayout.NAMES:
		check(d.has(name), "default has " + name)
	check(not d.fire2.enabled, "second fire button off by default")
	check(d.has("mic") and d.has("speaker"), "voice buttons are part of the layout")
	near(TouchLayout.position(d, "mic", size).x, 1280 - 46, 0.01, "mic under the pause button")
	var fire := TouchLayout.position(d, "fire", size)
	near(fire.x, 1280 - 155, 0.01, "fire default x")
	near(fire.y, 720 - 165, 0.01, "fire default y")
	# a partial, out-of-range saved layout resolves to something sane
	var saved := {"fire": {"x": 2.0, "y": -1.0, "s": 9.0}, "fire2": {"enabled": true}, "junk": 5}
	var r := TouchLayout.resolve(saved, size)
	near(r.fire.x, 0.97, 0.0001, "x clamped")
	near(r.fire.y, 0.05, 0.0001, "y clamped")
	near(r.fire.s, TouchLayout.MAX_SCALE, 0.0001, "scale clamped")
	check(r.fire2.enabled, "fire2 enabled from saved data")
	near(TouchLayout.position(r, "reload", size).x, 1280 - 300, 0.01, "untouched control keeps its default")
	# a different aspect ratio keeps normalised positions
	var wide := Vector2(1600, 720)
	near(TouchLayout.position(r, "fire", wide).x, 0.97 * 1600, 0.01, "normalised x scales with width")


func test_place_keeps_inside() -> void:
	var size := Vector2(1280, 720)
	var d := TouchLayout.defaults(size)
	TouchLayout.place(d, "switch", Vector2(-50, 5000), size)
	var p := TouchLayout.position(d, "switch", size)
	near(p.x, 0.03 * 1280, 0.01, "left edge")
	near(p.y, 0.95 * 720, 0.01, "bottom edge")
	TouchLayout.place(d, "stick", Vector2(300, 400), size)
	near(TouchLayout.position(d, "stick", size).x, 300, 0.01, "stick moved")
