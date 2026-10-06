extends Node2D
## Ritar kartan: mark (GPU-mesh per kartbit), vägar, samt "objekt" (träd, buser, stenar, hus) djupsorterade per kartbit.
## Allt är platta, generiska platshållare (enkla former), inga konstverk.

const Iso = preload("res://scripts/iso.gd")
const ChunkObjects = preload("res://scripts/chunk_objects.gd")
const CS := 32
const TREE_SCALE := 0.30
const OSM_EXAG := 2.4

const PAL := {
	0: Color("1f5d9c"), 1: Color("55a9db"), 2: Color("e0cf94"), 3: Color("79b24b"), 4: Color("386e34"),
	5: Color("cdb06a"), 6: Color("8f8a7c"), 7: Color("f4f7fa"), 8: Color("7f9f7d"), 9: Color("bdb7a8"),
}
# vägklasser: 3 stor, 1 huvudgata, 4 lokalgata, 2 järnväg  -> [kantbredd, fyllbredd, kantfärg, fyllfärg]
const ROADS := {
	3: [7.5, 5.4, Color(0.17, 0.17, 0.19), Color(0.40, 0.40, 0.43)],
	1: [5.6, 3.9, Color(0.23, 0.22, 0.22), Color(0.50, 0.49, 0.50)],
	4: [3.6, 2.4, Color(0.40, 0.37, 0.33), Color(0.70, 0.67, 0.61)],
	2: [3.4, 1.7, Color(0.18, 0.16, 0.14), Color(0.52, 0.50, 0.46)],
}
const WALLS := [Color("9a3b2b"), Color("a8442f"), Color("dcc072"), Color("ece6d6"), Color("c9b48a"), Color("9a3b2b"), Color("e3d3a1")]
const ROOFS := [Color("3b3b40"), Color("4a4a50"), Color("7d3a2d"), Color("5a2f28"), Color("56575c")]

var data
var res
var ground := Node2D.new()
var objects := Node2D.new()
var chunks := {}      # Vector2i -> {ground: Node2D, objects: MeshInstance2D}
var dirty := {}
var noise := FastNoiseLite.new()
var chunks_w := 0
var chunks_h := 0
var ground_sprite: Sprite2D
var sprites

func setup(map_data, resmodel, sprite_lib = null) -> void:
	data = map_data
	res = resmodel
	sprites = sprite_lib
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	chunks_w = int(ceil(float(data.w) / CS))
	chunks_h = int(ceil(float(data.h) / CS))
	_setup_ground()
	add_child(ground)
	objects.z_index = 1
	objects.y_sort_enabled = true
	add_child(objects)
	res.changed.connect(func(c): dirty[c] = true)

func _setup_ground() -> void:
	var n: int = data.w * data.h
	var m1 := PackedByteArray()
	var m2 := PackedByteArray()
	m1.resize(n * 4)
	m2.resize(n * 4)
	var bio: PackedByteArray = data.biome
	for i in n:
		var b := bio[i]
		var k := i * 4
		if b == 0: m1[k] = 255
		elif b == 4: m1[k + 1] = 255
		elif b == 9: m1[k + 2] = 255
		elif b == 1: m1[k + 3] = 255
		elif b == 6: m2[k] = 255
		elif b == 8: m2[k + 1] = 255
		elif b == 10: m2[k + 2] = 255
		elif b == 2 or b == 5: m2[k + 3] = 255
	var i1 := Image.create_from_data(data.w, data.h, false, Image.FORMAT_RGBA8, m1)
	var i2 := Image.create_from_data(data.w, data.h, false, Image.FORMAT_RGBA8, m2)
	i1.generate_mipmaps()
	i2.generate_mipmaps()
	var ef := PackedFloat32Array()
	ef.resize(data.ew * data.eh)
	for i in ef.size():
		ef[i] = data.elev[i]
	var ie := Image.create_from_data(data.ew, data.eh, false, Image.FORMAT_RF, ef.to_byte_array())
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("mask1", ImageTexture.create_from_image(i1))
	mat.set_shader_parameter("mask2", ImageTexture.create_from_image(i2))
	mat.set_shader_parameter("elev", ImageTexture.create_from_image(ie))
	mat.set_shader_parameter("map_size", Vector2(data.w, data.h))
	mat.set_shader_parameter("elev_size", Vector2(data.ew, data.eh))
	ground_sprite = Sprite2D.new()
	ground_sprite.texture = ImageTexture.create_from_image(i1)   # bara för storlek (UV 0..1 över kartan)
	ground_sprite.centered = false
	ground_sprite.material = mat
	ground_sprite.transform = Transform2D(Iso.to_screen(1, 0), Iso.to_screen(0, 1), Vector2.ZERO)
	ground_sprite.z_index = -1
	add_child(ground_sprite)

func _jitter(x: int, y: int) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)

func tile_color(x: int, y: int, b: int) -> Color:
	var base: Color = PAL.get(b, Color.MAGENTA)
	var shade := 1.0 + noise.get_noise_2d(x, y) * 0.07 + (_jitter(x, y) - 0.5) * 0.04
	if b == 3:
		# fält/ängar i fläckar (4x4 rutor)
		var ph := _jitter(x >> 2, y >> 2)
		if ph < 0.22:
			base = base.lerp(Color("c9b85e"), 0.55)
		elif ph < 0.38:
			base = base.lerp(Color("9ccf62"), 0.5)
		shade += (((x >> 2) + (y >> 2)) & 1) * 0.03
	if b >= 2:
		shade += (data.elev_at(x - 1.0, y - 1.0) - data.elev_at(x + 1.0, y + 1.0)) * 0.012
		if data.biome_at(x + 1, y) == 0 or data.biome_at(x - 1, y) == 0 or data.biome_at(x, y + 1) == 0 or data.biome_at(x, y - 1) == 0:
			base = base.lerp(PAL[2], 0.55)
	elif b == 0:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: int = data.biome_at(x + d.x, y + d.y)
			if nb >= 2 and nb != 10:
				base = base.lerp(Color(0.45, 0.72, 0.9), 0.5)
				break
	return Color(clampf(base.r * shade, 0, 1), clampf(base.g * shade, 0, 1), clampf(base.b * shade, 0, 1))

# ---------- mesh-hjälp ----------
func _tri(v: PackedVector2Array, c: PackedColorArray, a: Vector2, b: Vector2, d: Vector2, col: Color) -> void:
	v.append(a)
	v.append(b)
	v.append(d)
	c.append(col)
	c.append(col)
	c.append(col)

func _quad(v: PackedVector2Array, c: PackedColorArray, a: Vector2, b: Vector2, d: Vector2, e: Vector2, col: Color) -> void:
	_tri(v, c, a, b, d, col)
	_tri(v, c, a, d, e, col)

func _mesh(verts: PackedVector2Array, cols: PackedColorArray) -> MeshInstance2D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.mesh = m
	return mi

# ---------- vägar (mark ritas av shadern) ----------
func _build_ground(c: Vector2i, root: Node2D) -> bool:
	_build_roads(c, root)
	return true

func _road_half(v: PackedVector2Array, col: PackedColorArray, p0: Vector2, p1: Vector2, w: float, color: Color) -> void:
	var dir := (p1 - p0).normalized()
	var perp := Vector2(-dir.y, dir.x)
	_quad(v, col, p0 + perp * w, p0 - perp * w, p1 - perp * w, p1 + perp * w, color)

func _build_roads(c: Vector2i, root: Node2D) -> void:
	var cells: Array = []
	for ty in CS:
		for tx in CS:
			var r: int = data.road_at(c.x * CS + tx, c.y * CS + ty)
			if r != 0:
				cells.append(Vector3i(c.x * CS + tx, c.y * CS + ty, r))
	if cells.is_empty():
		return
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for pass_i in 2:
		var v := PackedVector2Array()
		var col := PackedColorArray()
		for cell in cells:
			var x: int = cell.x
			var y: int = cell.y
			var r: int = cell.z
			var p0 := Iso.to_screen(x + 0.5, y + 0.5)
			var spec: Array = ROADS[r]
			var w: float = spec[pass_i]
			var colr: Color = spec[2 + pass_i]
			_quad(v, col, p0 + Vector2(0, -w), p0 + Vector2(w * 1.6, 0), p0 + Vector2(0, w), p0 + Vector2(-w * 1.6, 0), colr)
			for d in dirs:
				var rn: int = data.road_at(x + d.x, y + d.y)
				if rn == 0 or (r == 2) != (rn == 2):
					continue
				if d.x != 0 and d.y != 0 and (data.road_at(x + d.x, y) != 0 or data.road_at(x, y + d.y) != 0):
					continue   # diagonal bara där den inte redan är ansluten via en rak väg (undviker X i korsningar)
				var p1 := Iso.to_screen(x + d.x + 0.5, y + d.y + 0.5)
				var mid := (p0 + p1) * 0.5
				var spec_n: Array = ROADS[rn]
				_road_half(v, col, p0, mid, w, colr)
				_road_half(v, col, mid, p1, float(spec_n[pass_i]), spec_n[2 + pass_i])
		root.add_child(_mesh(v, col))

# ---------- objekt: träd, buskar, stenar, hus (djupsorterade) ----------
func _tri3(v: PackedVector2Array, c: PackedColorArray, a: Vector2, b: Vector2, d: Vector2, ca: Color, cb: Color, cd: Color) -> void:
	v.append(a)
	v.append(b)
	v.append(d)
	c.append(ca)
	c.append(cb)
	c.append(cd)

func _fan(v: PackedVector2Array, c: PackedColorArray, centre: Vector2, rx: float, ry: float, c_in: Color, c_out: Color, n: int = 8, rot: float = 0.0) -> void:
	for i in n:
		var a0 := rot + TAU * i / n
		var a1 := rot + TAU * (i + 1) / n
		_tri3(v, c, centre, centre + Vector2(cos(a0) * rx, sin(a0) * ry), centre + Vector2(cos(a1) * rx, sin(a1) * ry), c_in, c_out, c_out)

func _shadow(v: PackedVector2Array, c: PackedColorArray, p: Vector2, rx: float, ry: float) -> void:
	_fan(v, c, p + Vector2(rx * 0.45, ry * 0.2), rx, ry, Color(0, 0, 0, 0.30), Color(0, 0, 0, 0.0), 8)

func _tree(v: PackedVector2Array, col: PackedColorArray, x: int, y: int, salt: int = 0) -> void:
	var j := _jitter(x * 3 + 1 + salt * 17, y * 7 + 2 + salt * 5)
	var j2 := _jitter(x * 5 + 7 + salt * 3, y * 11 + 1 + salt * 13)
	var p := Iso.to_screen(x + 0.15 + 0.7 * _jitter(x + salt * 9, y * 5 + 3), y + 0.15 + 0.7 * j)
	var s := 0.8 + 0.5 * j
	var biome: int = data.biome_at(x, y)
	var species := 0     # 0 gran, 1 tall, 2 björk, 3 ek
	if biome == 4:
		species = 0 if j2 < 0.55 else (1 if j2 < 0.78 else 2)
	else:
		species = 3 if j2 < 0.55 else 2
	_shadow(v, col, p, 10.0 * s, 3.8 * s)
	match species:
		0:
			var H := 30.0 * s
			_quad(v, col, p + Vector2(-1.4, 1), p + Vector2(1.4, 1), p + Vector2(1.4, -5), p + Vector2(-1.4, -5), Color("4a3524"))
			for k in 3:
				var by := p.y - H * 0.17 * k - 2.0
				var hw := 11.5 * s * (1.0 - 0.27 * k)
				var top := by - H * (0.46 if k < 2 else 0.5)
				var apex := Vector2(p.x, top)
				var low := Color(0.07, 0.20, 0.12)
				var hi := Color(0.17, 0.40, 0.22)
				var ml := Vector2(p.x, by + hw * 0.32)
				_tri3(v, col, apex, Vector2(p.x - hw, by), ml, hi.darkened(0.15), low, low.lightened(0.05))
				_tri3(v, col, apex, ml, Vector2(p.x + hw, by), hi.lightened(0.10), low.lightened(0.10), low.lightened(0.18))
		1:
			_quad(v, col, p + Vector2(-1.6, 1), p + Vector2(1.6, 1), p + Vector2(1.2, -18 * s), p + Vector2(-1.2, -18 * s), Color("6a4a30"))
			_fan(v, col, p + Vector2(-2 * s, -21 * s), 9 * s, 5.5 * s, Color(0.27, 0.42, 0.22), Color(0.12, 0.27, 0.14), 8)
			_fan(v, col, p + Vector2(4 * s, -25 * s), 7 * s, 4.5 * s, Color(0.30, 0.46, 0.24), Color(0.14, 0.30, 0.16), 8, 0.4)
		2:
			_quad(v, col, p + Vector2(-1.3, 1), p + Vector2(1.3, 1), p + Vector2(1.0, -12 * s), p + Vector2(-1.0, -12 * s), Color("e6e2d4"))
			_fan(v, col, p + Vector2(0, -17 * s), 8.5 * s, 8.0 * s, Color(0.55, 0.72, 0.30), Color(0.30, 0.50, 0.20), 9)
			_fan(v, col, p + Vector2(-2.5 * s, -19 * s), 4.5 * s, 4.0 * s, Color(0.68, 0.82, 0.38), Color(0.55, 0.72, 0.30), 7)
		_:
			_quad(v, col, p + Vector2(-2.2, 1), p + Vector2(2.2, 1), p + Vector2(1.7, -10 * s), p + Vector2(-1.7, -10 * s), Color("5a4026"))
			_fan(v, col, p + Vector2(0, -17 * s), 11.5 * s, 9.5 * s, Color(0.40, 0.58, 0.23), Color(0.20, 0.38, 0.15), 10)
			_fan(v, col, p + Vector2(-3 * s, -20 * s), 6.5 * s, 5.5 * s, Color(0.55, 0.72, 0.30), Color(0.38, 0.56, 0.22), 8)

func _bush(v: PackedVector2Array, col: PackedColorArray, x: int, y: int) -> void:
	var p := Iso.to_screen(x + 0.5, y + 0.5)
	_shadow(v, col, p, 8.0, 3.0)
	_fan(v, col, p + Vector2(0, -4), 8.0, 6.0, Color(0.44, 0.66, 0.30), Color(0.22, 0.42, 0.18), 8)
	for k in 5:
		var a := _jitter(x + k * 13, y + k * 7) * TAU
		var q := p + Vector2(-1 + cos(a) * 4.2, -4 + sin(a) * 3.0)
		_fan(v, col, q, 1.5, 1.5, Color("ff5a6a"), Color("c8283c"), 4)

func _rock(v: PackedVector2Array, col: PackedColorArray, x: int, y: int) -> void:
	var p := Iso.to_screen(x + 0.5, y + 0.5)
	_shadow(v, col, p, 10.0, 3.4)
	_tri3(v, col, p + Vector2(-9, 2), p + Vector2(-3, -10), p + Vector2(1, 3), Color("7b7f87"), Color("a4a8b0"), Color("62666e"))
	_tri3(v, col, p + Vector2(-3, -10), p + Vector2(10, 1), p + Vector2(1, 3), Color("b8bcc4"), Color("8d919a"), Color("6f737b"))

func _windows(v: PackedVector2Array, col: PackedColorArray, p0: Vector2, p1: Vector2, hh: float, lv: int, shade: float) -> void:
	# fönsterrader på en vägg mellan p0 och p1 (nederkant), höjd hh
	var len := p0.distance_to(p1)
	var n := int(len / 9.0)
	if n < 1 or hh < 9.0:
		return
	var rows := clampi(lv, 1, 8)
	for r in rows:
		var ty0 := (float(r) + 0.28) / rows
		var ty1 := (float(r) + 0.68) / rows
		for k in n:
			var t0 := (float(k) + 0.25) / n
			var t1 := (float(k) + 0.65) / n
			var a := p0.lerp(p1, t0)
			var b := p0.lerp(p1, t1)
			var up0 := Vector2(0, -hh * ty0)
			var up1 := Vector2(0, -hh * ty1)
			_quad(v, col, a + up0, b + up0, b + up1, a + up1, Color(0.30, 0.42, 0.55).darkened(shade))

func _building(v: PackedVector2Array, col: PackedColorArray, i: int) -> void:
	var b: PackedInt32Array = data.bld
	var x: float = b[i] / 4.0
	var y: float = b[i + 1] / 4.0
	var w: float = b[i + 2] / 4.0
	var h: float = b[i + 3] / 4.0
	var kind: int = b[i + 4] / 16
	var lv: int = b[i + 4] % 16
	var hh := 5.0 + 3.4 * float(lv) if kind != 2 else 7.0 + 1.6 * float(lv)
	var j := _jitter(b[i], b[i + 1])
	var wall: Color = WALLS[int(j * 7) % 7]
	var roof: Color = ROOFS[int(j * 5) % 5]
	match kind:
		1:
			wall = Color("d9d3c0") if j < 0.6 else Color("c9a46a")
			roof = Color("6b6c72")
		2:
			wall = Color("a3acb5")
			roof = Color("7b848d")
		3:
			wall = Color("ece4cc")
			roof = Color("8a3f30")
	var A := Iso.to_screen(x, y)
	var B := Iso.to_screen(x + w, y)
	var C := Iso.to_screen(x + w, y + h)
	var D := Iso.to_screen(x, y + h)
	var up := Vector2(0, -hh)
	var sh := Vector2(5, 2)
	_tri3(v, col, A + sh, B + sh + Vector2(3, 0), C + sh + Vector2(4, 2), Color(0, 0, 0, 0.26), Color(0, 0, 0, 0.12), Color(0, 0, 0, 0.0))
	_tri3(v, col, A + sh, C + sh + Vector2(4, 2), D + sh + Vector2(2, 3), Color(0, 0, 0, 0.26), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.12))
	# väggar med ljus-/mörkgradient
	_quad(v, col, D, C, C + up, D + up, wall.darkened(0.32))
	_quad(v, col, C, B, B + up, C + up, wall.darkened(0.12))
	# sockel
	_quad(v, col, D, C, C + Vector2(0, -2), D + Vector2(0, -2), wall.darkened(0.5))
	_quad(v, col, C, B, B + Vector2(0, -2), C + Vector2(0, -2), wall.darkened(0.4))
	if kind != 2 and (hh >= 9.0):
		_windows(v, col, D, C, hh, mini(lv, 6), 0.1)
		_windows(v, col, C, B, hh, mini(lv, 6), -0.05)
	elif kind == 2:
		for k in 5:
			var t := (float(k) + 0.5) / 5.0
			_quad(v, col, D.lerp(C, t - 0.02), D.lerp(C, t + 0.02), D.lerp(C, t + 0.02) + up, D.lerp(C, t - 0.02) + up, wall.darkened(0.45))
	if kind == 0 or kind == 3:
		var rh := 3.5 + 0.9 * minf(w, h) * 10.0
		var over := 1.5
		if w >= h:
			var r0 := Iso.to_screen(x, y + h * 0.5) + up + Vector2(0, -rh)
			var r1 := Iso.to_screen(x + w, y + h * 0.5) + up + Vector2(0, -rh)
			_quad(v, col, A + up + Vector2(0, -over), B + up + Vector2(0, -over), r1, r0, roof.darkened(0.18))
			_quad(v, col, r0, r1, C + up + Vector2(0, over), D + up + Vector2(0, over), roof)
			_quad(v, col, r0.lerp(r1, 0.62) + Vector2(-1.5, 0), r0.lerp(r1, 0.62) + Vector2(1.5, 0), r0.lerp(r1, 0.62) + Vector2(1.5, -5), r0.lerp(r1, 0.62) + Vector2(-1.5, -5), Color("6a3a2e"))
		else:
			var r0 := Iso.to_screen(x + w * 0.5, y) + up + Vector2(0, -rh)
			var r1 := Iso.to_screen(x + w * 0.5, y + h) + up + Vector2(0, -rh)
			_quad(v, col, A + up + Vector2(0, -over), r0, r1, D + up + Vector2(0, -over), roof.darkened(0.18))
			_quad(v, col, r0, B + up + Vector2(0, -over), C + up + Vector2(0, over), r1, roof)
			_quad(v, col, r0.lerp(r1, 0.4) + Vector2(-1.5, 0), r0.lerp(r1, 0.4) + Vector2(1.5, 0), r0.lerp(r1, 0.4) + Vector2(1.5, -5), r0.lerp(r1, 0.4) + Vector2(-1.5, -5), Color("6a3a2e"))
	else:
		_quad(v, col, A + up, B + up, C + up, D + up, roof)
		_quad(v, col, A + up, B + up, B + up + Vector2(0, 1.5), A + up + Vector2(0, 1.5), roof.lightened(0.15))

func _tree_name(x: int, y: int, salt: int) -> String:
	var j2 := _jitter(x * 5 + 7 + salt * 3, y * 11 + 1 + salt * 13)
	var b: int = data.biome_at(x, y)
	var sz2: String = ["S", "M"][int(j2 * 97.0) % 2]
	var sz3: String = ["S", "M", "L"][int(j2 * 89.0) % 3]
	if b == 4:
		if j2 < 0.55:
			return "spruce_" + sz3
		if j2 < 0.78:
			return "pine_" + sz2
		return "birch_" + sz2
	return ("oak_" if j2 < 0.55 else "birch_") + sz2

func _osm_building_name(kind: int, lv: int, len_m: float, j: float) -> String:
	match kind:
		1:
			return "block_%s_%d" % [["cream", "brick", "grey"][int(j * 3) % 3], clampi(lv, 3, 6)]
		2:
			return "industrial_a" if len_m < 24.0 else "industrial_b"
		3:
			return "church" if j < 0.3 else "school"
	var cols := ["red", "yellow", "white", "ochre", "grey"]
	var sk := "S" if len_m < 9.5 else ("M" if len_m < 12.5 else "L")
	return "house_%s_%s" % [cols[int(j * 5) % 5], sk]

func _build_object_node(c: Vector2i):
	var node = ChunkObjects.new()
	node.sprites = sprites
	var centre := Iso.to_screen(c.x * CS + CS * 0.5, c.y * CS + CS * 0.5)
	node.position = centre
	var list: Array = []   # [djup, namn, pos, skala, flip, skuggskala]
	for ty in CS:
		for tx in CS:
			var x := c.x * CS + tx
			var y := c.y * CS + ty
			var k: int = res.kind_at(x, y)
			if k == 0 or data.biome_at(x, y) == 10:
				continue
			var j := _jitter(x * 3 + 1, y * 7 + 2)
			var j2 := _jitter(x, y * 5 + 3)
			match k:
				1:
					var p := Iso.to_screen(x + 0.15 + 0.7 * j2, y + 0.15 + 0.7 * j)
					var sc := TREE_SCALE * (0.85 + 0.3 * j)
					list.append([x + y + 0.15 + 0.7 * (j2 + j) * 0.5, _tree_name(x, y, 0), p, sc, j > 0.5, sc * 0.55])
					if data.biome_at(x, y) == 4:
						var j3 := _jitter(x * 3 + 18, y * 7 + 7)
						var j4 := _jitter(x + 9, y * 5 + 3)
						var p2 := Iso.to_screen(x + 0.15 + 0.7 * j4, y + 0.15 + 0.7 * j3)
						var sc2 := TREE_SCALE * (0.85 + 0.3 * j3)
						list.append([x + y + 0.15 + 0.7 * (j3 + j4) * 0.5, _tree_name(x, y, 1), p2, sc2, j3 > 0.5, sc2 * 0.55])
				2:
					list.append([x + y + 0.9, "bush", Iso.to_screen(x + 0.5, y + 0.5), 0.30, j > 0.5, 0.16])
				3:
					list.append([x + y + 0.9, "rock_a" if j < 0.5 else "rock_b", Iso.to_screen(x + 0.5, y + 0.5), 0.30, j2 > 0.5, 0.17])
	# OSM-byggnader (Borås-läge)
	var bl: PackedInt32Array = data.buildings_in_chunk(c)
	var b: PackedInt32Array = data.bld
	for i in bl:
		var bx: float = b[i] / 4.0
		var by: float = b[i + 1] / 4.0
		var bw: float = b[i + 2] / 4.0
		var bh: float = b[i + 3] / 4.0
		var kind: int = b[i + 4] / 16
		var lv: int = b[i + 4] % 16
		var len_m: float = maxf(bw, bh) * data.cell_m
		var j := _jitter(b[i], b[i + 1])
		var nm := _osm_building_name(kind, lv, len_m, j)
		if not sprites.has(nm):
			continue
		var ctr := Iso.to_screen(bx + bw * 0.5, by + bh * 0.5)
		var sc: float = sprites.scale_for_len(nm, len_m * OSM_EXAG, data.cell_m)
		list.append([bx + bw * 0.5 + by + bh * 0.5, nm, ctr, sc, bh > bw, sc * 1.1])
	list.sort_custom(func(a, b2): return a[0] < b2[0])
	for it in list:
		node.shadows.append([it[2] - centre + Vector2(it[5] * 40, it[5] * 14), it[5]])
		node.items.append([it[1], it[2] - centre, it[3], it[4]])
	return node if not list.is_empty() else null

func _build_objects(c: Vector2i) -> MeshInstance2D:
	var items: Array = []   # [djup, typ, a, b]
	for ty in CS:
		for tx in CS:
			var x := c.x * CS + tx
			var y := c.y * CS + ty
			var k: int = res.kind_at(x, y)
			if k != 0 and data.biome_at(x, y) != 10:
				items.append([x + y + 0.9, k, x, y])
	var bl: PackedInt32Array = data.buildings_in_chunk(c)
	for i in bl:
		var depth: float = (data.bld[i] + data.bld[i + 2]) / 4.0 + (data.bld[i + 1] + data.bld[i + 3]) / 4.0
		items.append([depth, 10, i, 0])
	items.sort_custom(func(a, b): return a[0] < b[0])
	var v := PackedVector2Array()
	var col := PackedColorArray()
	for it in items:
		match it[1]:
			1:
				_tree(v, col, it[2], it[3])
				if data.biome_at(it[2], it[3]) == 4:
					_tree(v, col, it[2], it[3], 1)
			2: _bush(v, col, it[2], it[3])
			3: _rock(v, col, it[2], it[3])
			10: _building(v, col, it[2])
	if v.size() == 0:
		return null
	return _mesh(v, col)

func build_chunk(c: Vector2i) -> void:
	var root := Node2D.new()
	ground.add_child(root)
	if not _build_ground(c, root):
		root.queue_free()
		chunks[c] = {"ground": null, "objects": null}
		return
	var mi = _build_object_node(c) if (sprites != null and sprites.ok) else _build_objects(c)
	if mi != null:
		objects.add_child(mi)
	chunks[c] = {"ground": root, "objects": mi}

func rebuild_objects(c: Vector2i) -> void:
	if not chunks.has(c):
		return
	var entry: Dictionary = chunks[c]
	if entry["objects"] != null:
		entry["objects"].queue_free()
	var mi = _build_object_node(c) if (sprites != null and sprites.ok) else _build_objects(c)
	if mi != null:
		objects.add_child(mi)
	entry["objects"] = mi

## cell_min/cell_max = synliga rutor -> bygg saknade kartbitar inom tidsbudget (mikrosekunder).
func update_visible(cell_min: Vector2, cell_max: Vector2, budget_us: int = 7000) -> int:
	var c0 := Vector2i(clampi(int(floor(cell_min.x / CS)), 0, chunks_w - 1), clampi(int(floor(cell_min.y / CS)), 0, chunks_h - 1))
	var c1 := Vector2i(clampi(int(floor(cell_max.x / CS)), 0, chunks_w - 1), clampi(int(floor(cell_max.y / CS)), 0, chunks_h - 1))
	var centre := Vector2((c0.x + c1.x) * 0.5, (c0.y + c1.y) * 0.5)
	var t0 := Time.get_ticks_usec()
	var built := 0
	for k in dirty.keys():
		rebuild_objects(k)
		dirty.erase(k)
		if Time.get_ticks_usec() - t0 > budget_us:
			return built
	var want: Array = []
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var k := Vector2i(cx, cy)
			if not chunks.has(k):
				want.append(k)
	if want.is_empty():
		return built
	want.sort_custom(func(a, b): return Vector2(a).distance_squared_to(centre) < Vector2(b).distance_squared_to(centre))
	for k in want:
		build_chunk(k)
		built += 1
		if Time.get_ticks_usec() - t0 > budget_us:
			break
	return built

func chunk_count() -> int:
	return chunks.size()
