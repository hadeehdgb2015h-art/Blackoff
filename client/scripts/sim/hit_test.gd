class_name HitTest
extends RefCounted
## Ray tests against character hit shapes, mirrored on the server:
## a vertical body cylinder from the ankles to the neck plus a head sphere.

const FEET := 0.1


## Returns the distance along normalised ray d to sphere (c, r), or -1.
static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.length_squared() - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var s := sqrt(disc)
	var t := -b - s
	if t < 0.0:
		t = -b + s
	return t if t >= 0.0 else -1.0


## Ray vs finite vertical cylinder at base (x, z), from y0 to y1. Side surface only.
static func ray_cylinder(o: Vector3, d: Vector3, base: Vector2, y0: float, y1: float, r: float) -> float:
	var ox := o.x - base.x
	var oz := o.z - base.y
	var a := d.x * d.x + d.z * d.z
	if a < 1e-9:
		return -1.0
	var b := ox * d.x + oz * d.z
	var c := ox * ox + oz * oz - r * r
	var disc := b * b - a * c
	if disc < 0.0:
		return -1.0
	var s := sqrt(disc)
	for t in [(-b - s) / a, (-b + s) / a]:
		if t >= 0.0:
			var y: float = o.y + d.y * t
			if y >= y0 and y <= y1:
				return t
	return -1.0


## Tests a character. Returns {t, head} for the nearest hit, or {} on miss.
static func ray_character(o: Vector3, d: Vector3, pos: Vector2, radius: float, head_y: float, head_r: float) -> Dictionary:
	var th := ray_sphere(o, d, Vector3(pos.x, head_y, pos.y), head_r)
	var tb := ray_cylinder(o, d, pos, FEET, head_y - head_r, radius)
	if th >= 0.0 and (tb < 0.0 or th <= tb):
		return {"t": th, "head": true}
	if tb >= 0.0:
		return {"t": tb, "head": false}
	return {}
