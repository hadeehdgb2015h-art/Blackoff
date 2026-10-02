class_name MapData
extends RefCounted
## Gameplay geometry of a map, built from shared/maps/<id>.json.
## Same rules as the server: a flat plane (Godot x, z) with axis-aligned
## wall boxes. Boxes taller than stepHeight block movement; every box
## blocks bullets inside its own height range.

const BUCKET := 2.0

var id: String
var floor_height: float = 3.0
var bounds: Rect2
var walkable: Array[Rect2] = []
var wall_boxes: Array[AABB] = []
var move_rects: Array[Rect2] = []  ## walls that block movement (2D)
var player_spawns: Array = []      ## [{pos: Vector2, yaw: float}]
var zombie_entries: Array = []     ## [{id, pos: Vector2, inside: Vector2}]
var interactables: Array = []      ## [{id, kind, item, pos: Vector2, radius}]
var safe_area: Rect2

var _buckets := {}  ## Vector2i -> PackedInt32Array of move_rects indices


static func from_dict(d: Dictionary, step_height: float) -> MapData:
	var m := MapData.new()
	m.id = d.id
	m.floor_height = float(d.floorHeight)
	m.bounds = _rect(d.bounds)
	for w in d.walkable:
		m.walkable.append(_rect(w))
	for w in d.walls:
		var mn := Vector3(w.min[0], w.min[1], w.min[2])
		var mx := Vector3(w.max[0], w.max[1], w.max[2])
		m.wall_boxes.append(AABB(mn, mx - mn))
		if mx.y > step_height:
			m.move_rects.append(Rect2(Vector2(mn.x, mn.z), Vector2(mx.x - mn.x, mx.z - mn.z)))
	for s in d.playerSpawns:
		m.player_spawns.append({"pos": _v2(s.pos), "yaw": float(s.yaw)})
	for e in d.zombieEntries:
		m.zombie_entries.append({"id": e.id, "pos": _v2(e.pos), "inside": _v2(e.inside)})
	for it in d.interactables:
		m.interactables.append({"id": it.id, "kind": it.kind, "item": it.get("item", ""), "pos": _v2(it.pos), "radius": float(it.radius)})
	m.safe_area = _rect(d.safeArea)
	m._build_buckets()
	return m


func is_walkable(p: Vector2) -> bool:
	for r in walkable:
		if r.has_point(p):
			return true
	return false


## Moves a circle by delta with wall sliding. Sub-steps so fast movers
## cannot tunnel through thin walls.
func move_circle(pos: Vector2, delta: Vector2, radius: float) -> Vector2:
	var steps := maxi(1, ceili(delta.length() / (radius * 0.5)))
	var step := delta / steps
	for i in steps:
		pos = resolve_circle(pos + step, radius)
	return pos


## Pushes a circle out of every overlapping movement-blocking wall.
func resolve_circle(pos: Vector2, radius: float) -> Vector2:
	for _iter in 3:
		var moved := false
		for idx in query_rects(pos, radius):
			var r: Rect2 = move_rects[idx]
			var closest := Vector2(clampf(pos.x, r.position.x, r.end.x), clampf(pos.y, r.position.y, r.end.y))
			var diff := pos - closest
			var d2 := diff.length_squared()
			if d2 >= radius * radius:
				continue
			if d2 > 0.000001:
				var d := sqrt(d2)
				pos += diff / d * (radius - d)
			else:
				# Centre inside the box: leave along the shallowest axis.
				var left := pos.x - r.position.x
				var right := r.end.x - pos.x
				var top := pos.y - r.position.y
				var bottom := r.end.y - pos.y
				var m := minf(minf(left, right), minf(top, bottom))
				if m == left:
					pos.x = r.position.x - radius
				elif m == right:
					pos.x = r.end.x + radius
				elif m == top:
					pos.y = r.position.y - radius
				else:
					pos.y = r.end.y + radius
			moved = true
		if not moved:
			break
	return pos


## Distance along a normalised 3D ray to the first wall box, or max_dist.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var best := max_dist
	for box in wall_boxes:
		var t := ray_aabb(origin, dir, box, best)
		if t >= 0.0 and t < best:
			best = t
	return best


## True if a circle of the given radius can slide straight from a to b
## (used for path smoothing and direct chasing).
func segment_clear(a: Vector2, b: Vector2, radius: float) -> bool:
	var d := b - a
	var len := d.length()
	if len < 0.0001:
		return true
	var dir3 := Vector3(d.x / len, 0, d.y / len)
	var o3 := Vector3(a.x, 0.5, a.y)
	var grow := Vector3(radius, 0, radius)
	for idx in _query_segment(a, b):
		var r: Rect2 = move_rects[idx]
		var box := AABB(Vector3(r.position.x, 0, r.position.y) - grow, Vector3(r.size.x, 1, r.size.y) + grow * 2)
		var t := ray_aabb(o3, dir3, box, len)
		if t >= 0.0 and t <= len:
			return false
	return true


## Slab test. Returns entry distance (0 if origin inside) or -1.
static func ray_aabb(o: Vector3, d: Vector3, box: AABB, max_t: float) -> float:
	var tmin := 0.0
	var tmax := max_t
	var mn := box.position
	var mx := box.end
	for axis in 3:
		var oa := o[axis]
		var da := d[axis]
		if absf(da) < 1e-8:
			if oa < mn[axis] or oa > mx[axis]:
				return -1.0
		else:
			var inv := 1.0 / da
			var t1 := (mn[axis] - oa) * inv
			var t2 := (mx[axis] - oa) * inv
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


func _build_buckets() -> void:
	for i in move_rects.size():
		var r: Rect2 = move_rects[i].grow(1.0)
		for bx in range(floori(r.position.x / BUCKET), floori(r.end.x / BUCKET) + 1):
			for bz in range(floori(r.position.y / BUCKET), floori(r.end.y / BUCKET) + 1):
				var key := Vector2i(bx, bz)
				if not _buckets.has(key):
					_buckets[key] = PackedInt32Array()
				_buckets[key].append(i)


func query_rects(pos: Vector2, radius: float) -> PackedInt32Array:
	# Rects are bucketed with a 1 m margin, so one bucket covers radius <= 1.
	if radius <= 1.0:
		return _buckets.get(Vector2i(floori(pos.x / BUCKET), floori(pos.y / BUCKET)), PackedInt32Array())
	var out := PackedInt32Array()
	for i in move_rects.size():
		out.append(i)
	return out


## Candidate wall indices near a segment (bucket walk; radius must be <= 1).
func _query_segment(a: Vector2, b: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	var n := maxi(1, ceili(a.distance_to(b) / (BUCKET * 0.5)))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var key := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
		if seen.has(key):
			continue
		seen[key] = true
		for idx in _buckets.get(key, PackedInt32Array()):
			out.append(idx)
	return out


static func _rect(d: Dictionary) -> Rect2:
	var mn := _v2(d.min)
	return Rect2(mn, _v2(d.max) - mn)


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
