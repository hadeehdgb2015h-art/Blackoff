class_name NavGrid
extends RefCounted
## Navigation grid built from MapData (walkable floors minus walls inflated
## by the agent radius). The server builds the identical grid from the same
## map JSON with the same cell size and radius (constants.maps).

var map: MapData
var cell: float
var agent_radius: float
var astar := AStarGrid2D.new()
var size := Vector2i.ZERO
var origin := Vector2.ZERO


func _init(map_data: MapData, cell_size: float, radius: float) -> void:
	map = map_data
	cell = cell_size
	agent_radius = radius
	origin = map.bounds.position
	size = Vector2i(ceili(map.bounds.size.x / cell), ceili(map.bounds.size.y / cell))
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(cell, cell)
	astar.offset = origin + Vector2(cell, cell) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for x in size.x:
		for y in size.y:
			astar.set_point_solid(Vector2i(x, y), not _cell_open(Vector2i(x, y)))


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell), floori((p.y - origin.y) / cell))


func center_of(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell


func is_open(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


## World-space path from a to b (both snapped to the nearest open cell).
## Collinear points are dropped; agents skip ahead along the path when the
## next corner is in clear line (see SimZombie), which keeps this cheap.
## Empty if unreachable.
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca := nearest_open(cell_of(a))
	var cb := nearest_open(cell_of(b))
	if ca.x < 0 or cb.x < 0:
		return PackedVector2Array()
	var raw := astar.get_point_path(ca, cb)
	if raw.is_empty():
		return raw
	raw[raw.size() - 1] = b if map.is_walkable(b) else raw[raw.size() - 1]
	return _compress(raw)


## Spiral search for the closest open cell (agents pushed against walls).
func nearest_open(c: Vector2i, max_r: int = 4) -> Vector2i:
	if is_open(c):
		return c
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var n := c + Vector2i(dx, dy)
				if is_open(n):
					return n
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				var n := c + Vector2i(dx, dy)
				if is_open(n):
					return n
	return Vector2i(-1, -1)


func _compress(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for k in range(1, pts.size() - 1):
		var d0 := (pts[k] - pts[k - 1]).normalized()
		var d1 := (pts[k + 1] - pts[k]).normalized()
		if d0.dot(d1) < 0.999:
			out.append(pts[k])
	out.append(pts[pts.size() - 1])
	return out


func _cell_open(c: Vector2i) -> bool:
	var p := center_of(c)
	if not map.is_walkable(p):
		return false
	for idx in map.query_rects(p, agent_radius):
		if map.move_rects[idx].grow(agent_radius).has_point(p):
			return false
	return true
