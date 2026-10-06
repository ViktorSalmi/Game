extends Node2D
## Ritar kartan som GPU-meshar, en per kartbit (32x32 rutor), byggda lazy runt kameran.

const Iso = preload("res://scripts/iso.gd")
const CS := 32

const PAL := {
	0: Color("1f5d9c"), 1: Color("55a9db"), 2: Color("e0cf94"), 3: Color("79b24b"), 4: Color("386e34"),
	5: Color("cdb06a"), 6: Color("8f8a7c"), 7: Color("f4f7fa"), 8: Color("7f9f7d"), 9: Color("bdb7a8"),
}

var data
var chunks := {}
var noise := FastNoiseLite.new()
var chunks_w := 0
var chunks_h := 0

func setup(map_data) -> void:
	data = map_data
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	chunks_w = int(ceil(float(data.w) / CS))
	chunks_h = int(ceil(float(data.h) / CS))

func _jitter(x: int, y: int) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)

func tile_color(x: int, y: int, b: int) -> Color:
	var base: Color = PAL.get(b, Color.MAGENTA)
	var shade := 1.0 + noise.get_noise_2d(x, y) * 0.07 + (_jitter(x, y) - 0.5) * 0.04
	if b >= 2:
		shade += (data.elev_at(x - 1.0, y - 1.0) - data.elev_at(x + 1.0, y + 1.0)) * 0.012
		if data.biome_at(x + 1, y) == 0 or data.biome_at(x - 1, y) == 0 or data.biome_at(x, y + 1) == 0 or data.biome_at(x, y - 1) == 0:
			base = base.lerp(PAL[2], 0.55)
	elif b == 0:
		var near_land := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: int = data.biome_at(x + d.x, y + d.y)
			if nb >= 2 and nb != 10:
				near_land = true
		if near_land:
			base = base.lerp(Color(0.45, 0.72, 0.9), 0.5)
	return Color(clampf(base.r * shade, 0, 1), clampf(base.g * shade, 0, 1), clampf(base.b * shade, 0, 1))

func _add_quad(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	var base := verts.size()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	verts.append(d)
	for i in 4:
		cols.append(col)
	idx.append(base)
	idx.append(base + 1)
	idx.append(base + 2)
	idx.append(base)
	idx.append(base + 2)
	idx.append(base + 3)

func _mesh(verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> MeshInstance2D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.mesh = m
	return mi

func build_chunk(c: Vector2i) -> void:
	var root := Node2D.new()
	root.name = "chunk_%d_%d" % [c.x, c.y]
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var x0 := c.x * CS
	var y0 := c.y * CS
	for ty in CS:
		for tx in CS:
			var x := x0 + tx
			var y := y0 + ty
			var b: int = data.biome_at(x, y)
			if b == 10:
				continue
			_add_quad(verts, cols, idx, Iso.to_screen(x, y), Iso.to_screen(x + 1, y), Iso.to_screen(x + 1, y + 1), Iso.to_screen(x, y + 1), tile_color(x, y, b))
	if verts.size() > 0:
		root.add_child(_mesh(verts, cols, idx))
		_build_roads(c, root)
	add_child(root)
	chunks[c] = root

func _build_roads(c: Vector2i, root: Node2D) -> void:
	var cv := PackedVector2Array()
	var cc := PackedColorArray()
	var ci := PackedInt32Array()
	var x0 := c.x * CS
	var y0 := c.y * CS
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for ty in CS:
		for tx in CS:
			var x := x0 + tx
			var y := y0 + ty
			var r: int = data.road_at(x, y)
			if r == 0:
				continue
			var p0 := Iso.to_screen(x + 0.5, y + 0.5)
			var cw := 5.5 if r == 1 else 3.0
			var fw := 3.6 if r == 1 else 1.6
			var ccol := Color(0.30, 0.25, 0.18) if r == 1 else Color(0.12, 0.12, 0.12)
			var fcol := Color(0.93, 0.86, 0.66) if r == 1 else Color(0.62, 0.62, 0.62)
			_add_quad(cv, cc, ci, p0 + Vector2(0, -cw), p0 + Vector2(cw * 1.6, 0), p0 + Vector2(0, cw), p0 + Vector2(-cw * 1.6, 0), ccol)
			for d in dirs:
				if data.road_at(x + d.x, y + d.y) != r:
					continue
				var p1 := Iso.to_screen(x + d.x + 0.5, y + d.y + 0.5)
				var dir := (p1 - p0).normalized()
				var perp := Vector2(-dir.y, dir.x)
				_add_quad(cv, cc, ci, p0 + perp * cw, p0 - perp * cw, p1 - perp * cw, p1 + perp * cw, ccol)
	if cv.size() == 0:
		return
	var fv := PackedVector2Array()
	var fc := PackedColorArray()
	var fi := PackedInt32Array()
	for ty in CS:
		for tx in CS:
			var x := x0 + tx
			var y := y0 + ty
			var r: int = data.road_at(x, y)
			if r == 0:
				continue
			var p0 := Iso.to_screen(x + 0.5, y + 0.5)
			var fw := 3.6 if r == 1 else 1.6
			var fcol := Color(0.93, 0.86, 0.66) if r == 1 else Color(0.62, 0.62, 0.62)
			_add_quad(fv, fc, fi, p0 + Vector2(0, -fw), p0 + Vector2(fw * 1.6, 0), p0 + Vector2(0, fw), p0 + Vector2(-fw * 1.6, 0), fcol)
			for d in dirs:
				if data.road_at(x + d.x, y + d.y) != r:
					continue
				var p1 := Iso.to_screen(x + d.x + 0.5, y + d.y + 0.5)
				var dir := (p1 - p0).normalized()
				var perp := Vector2(-dir.y, dir.x)
				_add_quad(fv, fc, fi, p0 + perp * fw, p0 - perp * fw, p1 - perp * fw, p1 + perp * fw, fcol)
	root.add_child(_mesh(cv, cc, ci))
	root.add_child(_mesh(fv, fc, fi))

## cmin/cmax = synliga rutor (cell) -> bygg saknade kartbitar inom tidsbudget (mikrosekunder).
func update_visible(cell_min: Vector2, cell_max: Vector2, budget_us: int = 6000) -> int:
	var c0 := Vector2i(clampi(int(floor(cell_min.x / CS)), 0, chunks_w - 1), clampi(int(floor(cell_min.y / CS)), 0, chunks_h - 1))
	var c1 := Vector2i(clampi(int(floor(cell_max.x / CS)), 0, chunks_w - 1), clampi(int(floor(cell_max.y / CS)), 0, chunks_h - 1))
	var centre := Vector2((c0.x + c1.x) * 0.5, (c0.y + c1.y) * 0.5)
	var want: Array = []
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var k := Vector2i(cx, cy)
			if not chunks.has(k):
				want.append(k)
	if want.is_empty():
		return 0
	want.sort_custom(func(a, b): return Vector2(a).distance_squared_to(centre) < Vector2(b).distance_squared_to(centre))
	var t0 := Time.get_ticks_usec()
	var built := 0
	for k in want:
		build_chunk(k)
		built += 1
		if Time.get_ticks_usec() - t0 > budget_us:
			break
	return built

func chunk_count() -> int:
	return chunks.size()
