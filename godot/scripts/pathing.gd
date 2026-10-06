extends RefCounted
## Vägsökning över hela kartan (A* på rutnätet). Sjöar och utanför-kommunen är blockerade.

var grid := AStarGrid2D.new()
var data

func setup(map_data) -> void:
	data = map_data
	grid.region = Rect2i(0, 0, data.w, data.h)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y in data.h:
		for x in data.w:
			if not data.is_walkable(x, y):
				grid.set_point_solid(Vector2i(x, y), true)

func nearest_walkable(c: Vector2i, max_r: int = 30) -> Vector2i:
	if data.is_walkable(c.x, c.y):
		return c
	for r in range(1, max_r):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				if data.is_walkable(c.x + dx, c.y + dy):
					return Vector2i(c.x + dx, c.y + dy)
	return c

func find_path(from_c: Vector2i, to_c: Vector2i) -> Array[Vector2i]:
	var a := nearest_walkable(from_c)
	var b := nearest_walkable(to_c)
	var p: Array[Vector2i] = []
	for v in grid.get_id_path(a, b):
		p.append(v)
	return p
