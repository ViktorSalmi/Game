extends SceneTree
## Förrenderade isometriska sprites: bygger enkla 3D-modeller med kod, belyser dem och sparar PNG.
## Kör (kräver skärm, t.ex. xvfb):  godot --path godot --rendering-driver opengl3 -s tools/sprite_lab.gd -- --out=/sökväg/mapp

var SIZE := 256
var vp: SubViewport
var holder: Node3D
var cam3: Camera3D
var meta := {}

# ---------- procedurella texturer ----------
func _tex(w: int, h: int, f: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, f.call(x, y))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _n(x: int, y: int, s: int = 1) -> float:
	return fposmod(sin((x * 12.9898 + y * 78.233 + s * 37.7) ) * 43758.5453, 1.0)

func planks(base: Color, trim: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	return _tex(64, 64, func(x: int, y: int) -> Color:
		var plank := x % 8
		var c := base * (0.93 + 0.1 * _n(x / 8, y / 24, 3))
		if plank == 0:
			c = c.darkened(0.28)
		c = c * (0.96 + 0.08 * _n(x, y, 5))
		c.a = 1.0
		return c)

func tiles(base: Color) -> ImageTexture:
	return _tex(64, 64, func(x: int, y: int) -> Color:
		var row := y / 8
		var xx := (x + (row % 2) * 4) % 8
		var c := base * (0.88 + 0.2 * _n((x + (row % 2) * 4) / 8, row, 7))
		if y % 8 == 7 or xx == 0:
			c = c.darkened(0.35)
		c = c * (0.94 + 0.1 * _n(x, y, 9))
		c.a = 1.0
		return c)

func plaster(base: Color) -> ImageTexture:
	return _tex(64, 64, func(x: int, y: int) -> Color:
		var c := base * (0.93 + 0.12 * _n(x, y, 11))
		c.a = 1.0
		return c)

func mat(color: Color, tex: Texture2D = null, scale: Vector3 = Vector3.ONE, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color if tex == null else Color.WHITE
	if tex != null:
		m.albedo_texture = tex
		m.uv1_scale = scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = rough
	return m

func box(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func cone(parent: Node3D, pos: Vector3, r: float, h: float, m: Material, seg: int = 10) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)

func cyl(parent: Node3D, pos: Vector3, r: float, h: float, m: Material, seg: int = 8) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r * 0.85
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)

func ball(parent: Node3D, pos: Vector3, r: float, m: Material, sy: float = 1.0) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	mi.scale = Vector3(1, sy, 1)
	parent.add_child(mi)

# ---------- modeller (1 enhet = 1 meter) ----------
func hip_roof(n: Node3D, w: float, d: float, y: float, rh: float, m: Material) -> void:
	var pivot := Node3D.new()
	pivot.scale = Vector3(w + 1.0, rh, d + 1.0)
	pivot.position = Vector3(0, y + rh / 2, 0)
	n.add_child(pivot)
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.7071
	c.height = 1.0
	c.radial_segments = 4
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	mi.rotation_degrees = Vector3(0, 45, 0)
	pivot.add_child(mi)

func gable_roof(n: Node3D, w: float, d: float, y: float, rh: float, m: Material) -> void:
	var prism := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(d + 1.2, rh, w + 1.0)
	pm.left_to_right = 0.5
	prism.mesh = pm
	prism.material_override = m
	prism.rotation_degrees = Vector3(0, 90, 0)
	prism.position = Vector3(0, y + rh / 2 - 0.02, 0)
	n.add_child(prism)

func windows_front(n: Node3D, w: float, d: float, h: float, cols: int, rows: int, y0: float = 1.7, dy: float = 3.0, ww: float = 1.2, wh: float = 1.4) -> void:
	var glass := mat(Color(0.22, 0.32, 0.45), null, Vector3.ONE, 0.2)
	var frame := mat(Color("f4f0e6"))
	for r in rows:
		for i in cols:
			var x := -w / 2 + (i + 0.5) * w / cols
			box(n, Vector3(x, y0 + r * dy, d / 2 + 0.02), Vector3(ww + 0.3, wh + 0.3, 0.12), frame)
			box(n, Vector3(x, y0 + r * dy, d / 2 + 0.08), Vector3(ww, wh, 0.1), glass)
		var side := maxi(1, int(d / 3.2))
		for i in side:
			var z := -d / 2 + (i + 0.5) * d / side
			box(n, Vector3(w / 2 + 0.02, y0 + r * dy, z), Vector3(0.12, wh + 0.3, ww + 0.3), frame)
			box(n, Vector3(w / 2 + 0.08, y0 + r * dy, z), Vector3(0.1, wh, ww), glass)

func model_house(wall: Color, roof: Color, w: float = 9.0, d: float = 6.0, h: float = 4.6, wing: bool = false) -> Node3D:
	var n := Node3D.new()
	var wm := mat(wall, planks(wall), Vector3(w / 2.0, h / 2.0, 1))
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), wm)
	var trim := mat(Color("f1ece0"))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(n, Vector3(sx * (w / 2 - 0.12), h / 2, sz * (d / 2 - 0.12)), Vector3(0.28, h, 0.28), trim)
	box(n, Vector3(0, 0.12, 0), Vector3(w + 0.25, 0.25, d + 0.25), mat(Color("6d6a64")))
	var rm := mat(roof, tiles(roof), Vector3(w / 2.0, 2.0, 1), 0.8)
	var rh := 2.4 + d * 0.08
	gable_roof(n, w, d, h, rh, rm)
	box(n, Vector3(w * 0.25, h + rh * 0.8, -d * 0.12), Vector3(0.9, 2.0, 0.9), mat(Color("7a3b2d"), plaster(Color("8a4636"))))
	var cols := maxi(2, int(w / 3.0))
	windows_front(n, w * 0.78, d, h, cols, 1, h * 0.55, 3.0)
	box(n, Vector3(w * 0.38, 1.1, d / 2 + 0.05), Vector3(1.1, 2.1, 0.12), mat(Color("4a3220")))
	if wing:
		var wd := d * 0.55
		var ww := w * 0.35
		box(n, Vector3(w / 2 + ww / 2 - 0.4, h * 0.4, -d / 2 + wd / 2), Vector3(ww, h * 0.8, wd), wm)
		pass
	return n

func model_block(levels: int, wall: Color, w: float = 16.0, d: float = 9.0) -> Node3D:
	var n := Node3D.new()
	var h := 3.0 * levels
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), mat(wall, plaster(wall), Vector3(w / 3.0, h / 3.0, 1)))
	box(n, Vector3(0, 0.6, 0), Vector3(w + 0.3, 1.2, d + 0.3), mat(wall.darkened(0.35)))
	box(n, Vector3(0, h + 0.25, 0), Vector3(w + 0.5, 0.5, d + 0.5), mat(Color("6b6c72")))
	box(n, Vector3(w * 0.25, h + 1.0, 0), Vector3(2.4, 1.2, 2.4), mat(Color("8a8a90")))
	windows_front(n, w * 0.9, d, h, maxi(3, int(w / 2.8)), levels, 1.9, 3.0, 1.4, 1.5)
	box(n, Vector3(0, 1.3, d / 2 + 0.06), Vector3(1.8, 2.5, 0.14), mat(Color("3a3a3e")))
	return n

func model_industrial(w: float, d: float, wall: Color, sawtooth: bool) -> Node3D:
	var n := Node3D.new()
	var h := 6.0
	var corr := _tex(32, 32, func(x: int, y: int) -> Color:
		var c := wall * (0.85 + 0.2 * (0.5 + 0.5 * sin(x * 1.2)))
		c.a = 1.0
		return c)
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), mat(wall, corr, Vector3(w / 2.0, 1, 1)))
	if sawtooth:
		var k := int(w / 5.0)
		for i in k:
			var prism := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(d, 2.6, w / k)
			pm.left_to_right = 0.0
			prism.mesh = pm
			prism.material_override = mat(Color("6d7680"))
			prism.rotation_degrees = Vector3(0, 90, 0)
			prism.position = Vector3(-w / 2 + (i + 0.5) * w / k, h + 1.3, 0)
			n.add_child(prism)
	else:
		gable_roof(n, w, d, h, 2.0, mat(Color("7b848d")))
	box(n, Vector3(-w * 0.2, 2.2, d / 2 + 0.05), Vector3(4.0, 4.0, 0.14), mat(Color("3d4650")))
	box(n, Vector3(w * 0.2, 2.2, d / 2 + 0.05), Vector3(4.0, 4.0, 0.14), mat(Color("3d4650")))
	cyl(n, Vector3(w * 0.38, h + 5.0, -d * 0.2), 0.9, 8.0, mat(Color("7a6a5e")), 10)
	return n

func model_church() -> Node3D:
	var n := Node3D.new()
	var wall := Color("ece4cc")
	var wm := mat(wall, plaster(wall), Vector3(3, 2, 1))
	box(n, Vector3(0, 3.5, 0), Vector3(16.0, 7.0, 8.0), wm)
	gable_roof(n, 16.0, 8.0, 7.0, 4.0, mat(Color("8a3f30"), tiles(Color("8a3f30")), Vector3(8, 2, 1)))
	box(n, Vector3(-9.0, 7.0, 0), Vector3(4.4, 14.0, 4.4), wm)
	cone(n, Vector3(-9.0, 17.0, 0), 3.6, 6.0, mat(Color("3d4a52")), 4)
	box(n, Vector3(-9.0, 20.5, 0), Vector3(0.2, 1.6, 0.2), mat(Color("d9b040")))
	windows_front(n, 14.0, 8.0, 7.0, 4, 1, 3.8, 3.0, 1.0, 2.6)
	return n

func model_school() -> Node3D:
	var n := Node3D.new()
	var wall := Color("a85a42")
	box(n, Vector3(0, 5.0, 0), Vector3(22.0, 10.0, 9.0), mat(wall, plaster(wall), Vector3(5, 3, 1)))
	hip_roof(n, 22.0, 9.0, 10.0, 3.5, mat(Color("45454b"), tiles(Color("45454b")), Vector3(8, 2, 1)))
	windows_front(n, 20.0, 9.0, 10.0, 7, 3, 1.9, 3.0, 1.3, 1.5)
	box(n, Vector3(0, 1.3, 4.56), Vector3(2.4, 2.6, 0.14), mat(Color("3a3a3e")))
	return n

func model_spruce(s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	cyl(n, Vector3(0, 1.0 * s, 0), 0.28 * s, 2.0 * s, mat(Color("4a3524")))
	for k in 5:
		var m := mat(Color(0.06 + 0.012 * k, 0.20 + 0.025 * k, 0.11 + 0.01 * k))
		cone(n, Vector3(0, (1.6 + k * 1.45) * s, 0), (2.9 - k * 0.5) * s, 2.6 * s, m, 10)
	return n

func model_pine(s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	cyl(n, Vector3(0, 3.6 * s, 0), 0.30 * s, 7.2 * s, mat(Color("7a5236")), 8)
	var g := [Color("2e5a30"), Color("3a6a34"), Color("274f2c")]
	var offs := [Vector3(0, 7.4, 0), Vector3(1.6, 6.4, 0.6), Vector3(-1.5, 6.0, -0.8), Vector3(0.4, 8.4, 0.5)]
	for i in offs.size():
		ball(n, offs[i] * s, (2.1 - 0.2 * i) * s, mat(g[i % 3]), 0.55)
	return n

func model_birch(s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	cyl(n, Vector3(0, 2.6 * s, 0), 0.22 * s, 5.2 * s, mat(Color("e8e4d6")))
	var g := [Color("4a7a26"), Color("5a8a2e"), Color("3f6c20"), Color("6a9a34")]
	var offs := [Vector3(0, 6.2, 0), Vector3(1.2, 5.4, 0.5), Vector3(-1.1, 5.6, -0.6), Vector3(0.2, 7.2, 0.3), Vector3(-0.4, 5.2, 1.2)]
	for i in offs.size():
		ball(n, offs[i] * s, (1.7 - 0.12 * i) * s, mat(g[i % 4]), 0.9)
	return n

func model_oak(s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	cyl(n, Vector3(0, 2.0 * s, 0), 0.5 * s, 4.0 * s, mat(Color("5a4026")))
	var g := [Color("3f6a22"), Color("4d7a2a"), Color("365e1e"), Color("5a8830"), Color("446f26")]
	var offs := [Vector3(0, 6.0, 0), Vector3(2.4, 5.2, 0.8), Vector3(-2.2, 5.4, -0.8), Vector3(0.6, 7.2, 0.4), Vector3(-0.6, 5.0, 2.3), Vector3(1.0, 5.0, -2.2)]
	for i in offs.size():
		ball(n, offs[i] * s, (2.6 - 0.15 * i) * s, mat(g[i % 5]), 0.85)
	return n

func model_bush() -> Node3D:
	var n := Node3D.new()
	ball(n, Vector3(0, 0.9, 0), 1.2, mat(Color("3f7a30")), 0.8)
	ball(n, Vector3(0.9, 0.7, 0.4), 0.9, mat(Color("4a8a38")), 0.8)
	ball(n, Vector3(-0.8, 0.7, -0.3), 0.9, mat(Color("386e2a")), 0.8)
	for p in [Vector3(0.2, 1.7, 0.7), Vector3(-0.6, 1.4, 0.6), Vector3(1.0, 1.4, 0.9), Vector3(0.3, 1.5, -0.7)]:
		ball(n, p, 0.18, mat(Color("d4263c"), null, Vector3.ONE, 0.4))
	return n

func model_rock(seed_v: int = 0) -> Node3D:
	var n := Node3D.new()
	var base := Color("8a8e96")
	for i in 3:
		var r := 1.3 - i * 0.25
		var pos := Vector3(-0.9 + i * 0.9, r * 0.55, 0.3 * (i % 2) - 0.2)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 6
		sm.rings = 3
		sm.radius = r
		sm.height = r * 1.4
		mi.mesh = sm
		mi.material_override = mat(base.lightened(0.08 * i), plaster(base), Vector3.ONE, 0.95)
		mi.position = pos
		mi.rotation_degrees = Vector3(seed_v * 20 + i * 30, i * 50, 10)
		n.add_child(mi)
	return n

func model_person(shirt: Color, yaw_deg: float, frame: int, frames: int) -> Node3D:
	var root := Node3D.new()
	var n := Node3D.new()
	n.rotation_degrees = Vector3(0, yaw_deg, 0)
	root.add_child(n)
	var ph := TAU * float(frame) / float(frames) if frame >= 0 else 0.0
	var swing := sin(ph) * 32.0 if frame >= 0 else 0.0
	var bob := absf(sin(ph)) * 0.04 if frame >= 0 else 0.0
	var skin := mat(Color("f1c9a0"))
	var pants := mat(Color("4a4036"))
	var top := mat(shirt)
	var sleeve := mat(shirt.darkened(0.18))
	box(n, Vector3(0, 1.05 + bob, 0), Vector3(0.52, 0.72, 0.28), top)
	ball(n, Vector3(0, 1.62 + bob, 0), 0.22, skin)
	ball(n, Vector3(0, 1.70 + bob, -0.03), 0.23, mat(Color("4a3322")), 0.7)
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.14, 0.72 + bob, 0)
		leg.rotation_degrees = Vector3(swing * side, 0, 0)
		n.add_child(leg)
		box(leg, Vector3(0, -0.36, 0), Vector3(0.2, 0.72, 0.22), pants)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.36, 1.36 + bob, 0)
		arm.rotation_degrees = Vector3(-swing * side * 0.9, 0, 0)
		n.add_child(arm)
		box(arm, Vector3(0, -0.28, 0), Vector3(0.14, 0.56, 0.16), sleeve)
		box(arm, Vector3(0, -0.6, 0), Vector3(0.13, 0.12, 0.14), skin)
	return root

# ---------- era-modeller ----------
func thatch_tex() -> ImageTexture:
	return _tex(64, 64, func(x: int, y: int) -> Color:
		var c := Color(0.78, 0.66, 0.36) * (0.82 + 0.3 * _n(x / 2, y / 6, 21))
		if y % 8 == 7:
			c = c.darkened(0.25)
		c.a = 1.0
		return c)

func stone_tex(base: Color) -> ImageTexture:
	return _tex(64, 64, func(x: int, y: int) -> Color:
		var row := y / 10
		var xx := (x + (row % 2) * 8) % 16
		var c := base * (0.8 + 0.3 * _n((x + (row % 2) * 8) / 16, row, 31))
		if y % 10 == 9 or xx == 15:
			c = c.darkened(0.4)
		c.a = 1.0
		return c)

func rows_tex(a: Color, b: Color) -> ImageTexture:
	return _tex(64, 64, func(x: int, y: int) -> Color:
		var c := (a if (x / 4) % 2 == 0 else b) * (0.9 + 0.2 * _n(x, y, 41))
		c.a = 1.0
		return c)

func model_cave() -> Node3D:
	var n := Node3D.new()
	var rock := mat(Color("7a7266"), stone_tex(Color("8a8274")), Vector3(2, 2, 1), 0.95)
	var rock2 := mat(Color("6a6358"), stone_tex(Color("746c60")), Vector3(2, 2, 1), 0.95)
	ball(n, Vector3(-1.5, 3.0, -1.0), 5.2, rock, 0.8)
	ball(n, Vector3(2.5, 2.4, -2.2), 4.2, rock2, 0.8)
	ball(n, Vector3(-3.5, 2.0, 2.4), 3.6, rock2, 0.8)
	ball(n, Vector3(0.6, 3.6, -3.4), 4.4, rock, 0.75)
	ball(n, Vector3(4.6, 1.2, 0.6), 2.6, rock, 0.8)
	ball(n, Vector3(0.6, 1.2, 4.6), 2.6, rock2, 0.8)
	var dark := mat(Color(0.02, 0.018, 0.015), null, Vector3.ONE, 1.0)
	ball(n, Vector3(2.2, 2.0, 2.2), 3.7, rock, 0.85)
	var pivot := Node3D.new()
	n.add_child(pivot)
	var mp := Vector3(4.5, 1.5, 4.5)
	pivot.look_at_from_position(mp, mp + Vector3(1.0, 0.1, 1.0), Vector3.UP)
	var mouth := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mouth.mesh = sm
	mouth.material_override = dark
	mouth.scale = Vector3(1.55, 1.9, 0.3)
	pivot.add_child(mouth)
	for k in 7:
		var a := PI * (0.05 + 0.9 * float(k) / 6.0)
		var pr := Node3D.new()
		n.add_child(pr)
		var off := Vector3(cos(a) * 1.75, sin(a) * 2.1 - 0.2, 0.0)
		var basis_pos := mp + pivot.global_transform.basis.x * off.x + Vector3.UP * off.y
		ball(n, basis_pos, 0.62, rock2, 0.8)
	for p in [Vector3(2.4, 0.4, 5.2), Vector3(5.4, 0.4, 2.2), Vector3(3.2, 3.6, 3.2)]:
		ball(n, p, 0.8, rock2, 0.7)
	for p in [Vector3(-2.0, 5.5, -0.5), Vector3(1.0, 5.9, -2.8)]:
		ball(n, p, 1.0, mat(Color("4a7a30")), 0.5)
	return n

func model_tent(hide: Color) -> Node3D:
	var n := Node3D.new()
	var m := mat(hide, plaster(hide), Vector3(3, 2, 1), 0.95)
	cone(n, Vector3(0, 2.0, 0), 2.7, 4.0, m, 7)
	box(n, Vector3(0.0, 0.9, 2.5), Vector3(1.0, 1.8, 0.08), mat(Color(0.05, 0.04, 0.03)))
	return n

func model_hut(wall: Color) -> Node3D:
	var n := Node3D.new()
	var th := mat(Color.WHITE, thatch_tex(), Vector3(3, 2, 1), 0.95)
	var wm := mat(wall, plaster(wall), Vector3(2, 1, 1), 0.95)
	cyl(n, Vector3(0, 1.1, 0), 2.6, 2.2, wm, 12)
	cone(n, Vector3(0, 3.7, 0), 3.5, 3.0, th, 12)
	box(n, Vector3(0.0, 0.9, 2.5), Vector3(1.0, 1.8, 0.1), mat(Color(0.12, 0.08, 0.05)))
	return n

func model_longhouse(big: bool = false) -> Node3D:
	var n := Node3D.new()
	var w := 16.0 if big else 12.0
	var d := 6.0 if big else 5.0
	var h := 2.6
	var wood := Color("7a5a38")
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), mat(wood, planks(wood), Vector3(w / 2.0, 1, 1)))
	var th := mat(Color.WHITE, thatch_tex(), Vector3(w / 2.0, 2, 1), 0.95)
	gable_roof(n, w, d, h, 3.4, th)
	box(n, Vector3(w * 0.3, 0.9, d / 2 + 0.05), Vector3(1.0, 1.8, 0.1), mat(Color(0.1, 0.07, 0.05)))
	box(n, Vector3(w / 2 + 0.05, 1.0, 0), Vector3(0.1, 1.9, 1.1), mat(Color(0.1, 0.07, 0.05)))
	return n

func model_timber(wood: Color, roof: Color, roof_thatch: bool) -> Node3D:
	var n := Node3D.new()
	var w := 10.0
	var d := 6.5
	var h := 4.4
	var plaster_c := Color("d8caa4")
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), mat(plaster_c, plaster(plaster_c), Vector3(w / 2.5, h / 2.5, 1)))
	var beam := mat(wood)
	for i in 6:
		var x := -w / 2 + i * w / 5.0
		box(n, Vector3(x, h / 2, d / 2 + 0.05), Vector3(0.28, h, 0.18), beam)
	for sz in [-1, 1]:
		box(n, Vector3(w / 2 + 0.05, h / 2, sz * d / 2 * 0.8), Vector3(0.18, h, 0.28), beam)
	box(n, Vector3(0, h * 0.5, d / 2 + 0.05), Vector3(w, 0.22, 0.18), beam)
	box(n, Vector3(0, h - 0.1, d / 2 + 0.05), Vector3(w, 0.25, 0.2), beam)
	var rm := mat(Color.WHITE, thatch_tex(), Vector3(w / 2.0, 2, 1), 0.95) if roof_thatch else mat(roof, tiles(roof), Vector3(w / 2.0, 2, 1), 0.8)
	gable_roof(n, w, d, h, 3.2, rm)
	windows_front(n, w * 0.7, d, h, 3, 1, h * 0.55, 3.0, 1.0, 1.2)
	box(n, Vector3(w * 0.38, 1.1, d / 2 + 0.1), Vector3(1.1, 2.1, 0.12), mat(Color("4a3220")))
	box(n, Vector3(w * 0.25, h + 2.6, -d * 0.12), Vector3(0.9, 2.0, 0.9), mat(Color("77716a"), stone_tex(Color("8a8479"))))
	return n

func model_stonehouse(stone: Color, roof: Color) -> Node3D:
	var n := Node3D.new()
	var w := 10.0
	var d := 7.0
	var h := 5.6
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), mat(stone, stone_tex(stone), Vector3(w / 3.0, h / 3.0, 1)))
	gable_roof(n, w, d, h, 3.2, mat(roof, tiles(roof), Vector3(w / 2.0, 2, 1), 0.8))
	windows_front(n, w * 0.7, d, h, 3, 2, 1.8, 2.6, 0.9, 1.3)
	box(n, Vector3(w * 0.38, 1.2, d / 2 + 0.1), Vector3(1.2, 2.3, 0.12), mat(Color("4a3220")))
	box(n, Vector3(w * 0.28, h + 2.8, -d * 0.1), Vector3(1.0, 2.4, 1.0), mat(Color("77716a"), stone_tex(Color("8a8479"))))
	return n

func model_field(gold: bool) -> Node3D:
	var n := Node3D.new()
	var a := Color("c9b04a") if gold else Color("5a9a38")
	var b := Color("a68a36") if gold else Color("447a2c")
	box(n, Vector3(0, 0.12, 0), Vector3(21.0, 0.24, 21.0), mat(Color("5a4630")))
	box(n, Vector3(0, 0.3, 0), Vector3(19.5, 0.2, 19.5), mat(Color.WHITE, rows_tex(a, b), Vector3(5, 5, 1), 0.95))
	return n

func model_camp(stone: bool) -> Node3D:
	var n := Node3D.new()
	for p in [Vector3(-2.2, 0, -1.4), Vector3(2.2, 0, -1.4), Vector3(-2.2, 0, 1.6), Vector3(2.2, 0, 1.6)]:
		box(n, p + Vector3(0, 1.6, 0), Vector3(0.3, 3.2, 0.3), mat(Color("5a4026")))
	box(n, Vector3(0, 3.4, 0.1), Vector3(5.6, 0.35, 4.4), mat(Color("6a4a2c"), planks(Color("6a4a2c")), Vector3(3, 2, 1)))
	if stone:
		for i in 6:
			var r := 0.7 + 0.15 * (i % 3)
			ball(n, Vector3(-4.0 + (i % 3) * 1.4, r * 0.5, 3.6 + (i / 3) * 1.3), r, mat(Color("8d9199")), 0.7)
	else:
		for i in 5:
			var c := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.4
			cm.bottom_radius = 0.4
			cm.height = 4.2
			c.mesh = cm
			c.material_override = mat(Color("8a5a30"), planks(Color("8a5a30")), Vector3(1, 1, 1))
			c.rotation_degrees = Vector3(0, 0, 90)
			c.position = Vector3(-4.2, 0.4 + (i / 3) * 0.7, 3.4 + (i % 3) * 0.85)
			n.add_child(c)
	box(n, Vector3(0, 0.5, 0.3), Vector3(2.0, 1.0, 1.4), mat(Color("7a6040")))
	return n

func model_keep() -> Node3D:
	var n := Node3D.new()
	var st := Color("8f8a80")
	var sm := mat(st, stone_tex(st), Vector3(4, 4, 1))
	box(n, Vector3(0, 7.0, 0), Vector3(12.0, 14.0, 12.0), sm)
	for i in 6:
		var t := -5.0 + i * 2.0
		for side in [-1, 1]:
			box(n, Vector3(t, 14.6, side * 5.6), Vector3(1.2, 1.3, 0.8), sm)
			box(n, Vector3(side * 5.6, 14.6, t), Vector3(0.8, 1.3, 1.2), sm)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			cyl(n, Vector3(sx * 6.0, 8.0, sz * 6.0), 2.2, 16.0, sm, 10)
			cone(n, Vector3(sx * 6.0, 18.0, sz * 6.0), 2.8, 4.0, mat(Color("7a3f33")), 10)
	box(n, Vector3(0, 2.2, 6.1), Vector3(2.6, 4.4, 0.2), mat(Color("3a2a1c")))
	windows_front(n, 9.0, 12.0, 14.0, 3, 2, 6.0, 4.0, 0.9, 1.6)
	return n

func model_campfire() -> Node3D:
	var n := Node3D.new()
	for i in 10:
		var a := TAU * i / 10.0
		ball(n, Vector3(cos(a) * 1.5, 0.3, sin(a) * 1.5), 0.45, mat(Color("8d9199")), 0.7)
	for k in 3:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.16
		cm.height = 2.2
		c.mesh = cm
		c.material_override = mat(Color("5a3a22"))
		c.rotation_degrees = Vector3(70, k * 60, 0)
		c.position = Vector3(0, 0.5, 0)
		n.add_child(c)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("ff8a1e")
	fm.emission_enabled = true
	fm.emission = Color("ff7a10")
	fm.emission_energy_multiplier = 2.0
	cone(n, Vector3(0, 1.3, 0), 0.75, 1.8, fm, 8)
	var fm2 := StandardMaterial3D.new()
	fm2.albedo_color = Color("ffd24a")
	fm2.emission_enabled = true
	fm2.emission = Color("ffd24a")
	fm2.emission_energy_multiplier = 2.0
	cone(n, Vector3(0, 1.1, 0), 0.4, 1.1, fm2, 8)
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var seat := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.3
		sm.bottom_radius = 0.3
		sm.height = 1.8
		seat.mesh = sm
		seat.material_override = mat(Color("6a4a2c"), planks(Color("6a4a2c")), Vector3(1, 1, 1))
		seat.rotation_degrees = Vector3(0, -rad_to_deg(a), 90)
		seat.position = Vector3(cos(a) * 3.4, 0.35, sin(a) * 3.4)
		n.add_child(seat)
	for sgn in [-1, 1]:
		var base := Vector3(sgn * 4.6, 0, -2.4)
		box(n, base + Vector3(-0.6, 1.2, 0), Vector3(0.18, 2.4, 0.18), mat(Color("5a4026")))
		box(n, base + Vector3(0.6, 1.2, 0), Vector3(0.18, 2.4, 0.18), mat(Color("5a4026")))
		box(n, base + Vector3(0, 2.3, 0), Vector3(1.6, 0.14, 0.14), mat(Color("5a4026")))
		box(n, base + Vector3(0, 1.5, 0), Vector3(1.1, 1.4, 0.06), mat(Color("a8845a")))
	return n

func model_hall_long() -> Node3D:
	var n := model_longhouse(true)
	box(n, Vector3(-8.2, 3.0, 0), Vector3(0.3, 6.0, 0.3), mat(Color("5a4026")))
	box(n, Vector3(-8.2, 5.6, 1.0), Vector3(0.1, 1.6, 2.0), mat(Color("b8302a")))
	return n

# ---------- rendering ----------
func _setup(size_px: int) -> void:
	SIZE = size_px
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(-8, 14, 10), Vector3.ZERO)
	cam3 = Camera3D.new()
	cam3.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam3)
	holder = Node3D.new()
	vp.add_child(holder)
	# skuggfångare: osynlig mark som bara visar skuggor
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode blend_mix, shadow_to_opacity, depth_draw_never;\nvoid fragment(){ ALBEDO = vec3(0.0); ROUGHNESS = 1.0; }\n"
	var gm := ShaderMaterial.new()
	gm.shader = sh
	var plane := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(120, 120)
	plane.mesh = pmesh
	plane.material_override = gm
	plane.position = Vector3(0, -0.01, 0)
	vp.add_child(plane)

func shoot(node: Node3D, name: String, out: String, cam_size: float, target_y: float, len_m: float = 0.0) -> void:
	for c in holder.get_children():
		c.queue_free()
	holder.add_child(node)
	cam3.size = cam_size
	var tgt := Vector3(0, target_y, 0)
	cam3.look_at_from_position(Vector3(0.612, 0.5, 0.612) * 40.0 + tgt, tgt)
	for i in 4:
		await process_frame
	vp.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	var ppm := float(SIZE) / cam_size
	# var origo i bilden: mitten, förskjuten nedåt av målhöjden (pitch 30 grader)
	meta[name] = {"ax": SIZE / 2.0, "ay": SIZE / 2.0 + target_y * cos(deg_to_rad(30.0)) * ppm, "ppm": ppm, "len": len_m}

func _initialize() -> void:
	var out := "/tmp/sprites"
	var which := "all"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--set="):
			which = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	if which == "all" or which == "buildings":
		_setup(320)
		var walls := {"red": [Color("8c3626"), Color("34343a")], "yellow": [Color("c9a64e"), Color("6e3427")], "white": [Color("e4dfce"), Color("44444a")], "ochre": [Color("b98a45"), Color("5a2f28")], "grey": [Color("8c98a2"), Color("3d3d42")]}
		var sizes := {"S": [8.0, 5.6, 4.2], "M": [11.0, 7.0, 4.6], "L": [14.0, 9.0, 5.0]}
		for c in walls:
			for sk in sizes:
				var sz: Array = sizes[sk]
				await shoot(model_house(walls[c][0], walls[c][1], sz[0], sz[1], sz[2], sk == "L"), "house_%s_%s" % [c, sk], out, 24.0, 3.5, sz[0])
		var bw := {"cream": Color("d6cfb8"), "brick": Color("a35a40"), "grey": Color("a9aeb2")}
		for c in bw:
			for lv in [3, 4, 5, 6]:
				await shoot(model_block(lv, bw[c]), "block_%s_%d" % [c, lv], out, 30.0, 3.0 * lv * 0.5, 16.0)
		await shoot(model_industrial(20.0, 12.0, Color("9aa3ad"), false), "industrial_a", out, 34.0, 4.0, 20.0)
		await shoot(model_industrial(30.0, 16.0, Color("8f9aa6"), true), "industrial_b", out, 44.0, 4.0, 30.0)
		await shoot(model_church(), "church", out, 34.0, 8.0, 16.0)
		await shoot(model_school(), "school", out, 36.0, 6.0, 22.0)
		print("byggnader klara")
	if which == "all" or which == "eras":
		_setup(320)
		await shoot(model_cave(), "cave", out, 26.0, 3.0, 12.0)
		await shoot(model_tent(Color("a8845a")), "tent_a", out, 14.0, 2.0, 5.0)
		await shoot(model_tent(Color("8a7a5a")), "tent_b", out, 14.0, 2.0, 5.0)
		await shoot(model_hut(Color("9a7a58")), "hut_a", out, 14.0, 2.4, 6.0)
		await shoot(model_hut(Color("8a6a4a")), "hut_b", out, 14.0, 2.4, 6.0)
		await shoot(model_longhouse(false), "longhouse_a", out, 22.0, 2.6, 12.0)
		await shoot(model_longhouse(true), "longhouse_b", out, 26.0, 2.6, 16.0)
		await shoot(model_timber(Color("4a3626"), Color("7d3a2d"), true), "timber_a", out, 22.0, 3.4, 10.0)
		await shoot(model_timber(Color("3a2a1c"), Color("7d3a2d"), false), "timber_b", out, 22.0, 3.4, 10.0)
		await shoot(model_timber(Color("5a4630"), Color("5a2f28"), false), "timber_c", out, 22.0, 3.4, 10.0)
		await shoot(model_stonehouse(Color("9a958a"), Color("7d3a2d")), "stone_a", out, 22.0, 4.0, 10.0)
		await shoot(model_stonehouse(Color("a8a094"), Color("44444a")), "stone_b", out, 22.0, 4.0, 10.0)
		await shoot(model_stonehouse(Color("8a8f98"), Color("5a2f28")), "stone_c", out, 22.0, 4.0, 10.0)
		await shoot(model_field(false), "field_green", out, 34.0, 0.2, 20.0)
		await shoot(model_field(true), "field_gold", out, 34.0, 0.2, 20.0)
		await shoot(model_camp(false), "camp_wood", out, 20.0, 1.8, 6.0)
		await shoot(model_camp(true), "camp_stone", out, 20.0, 1.8, 6.0)
		await shoot(model_keep(), "hall_keep", out, 44.0, 8.0, 12.0)
		await shoot(model_hall_long(), "hall_long", out, 30.0, 3.0, 16.0)
		await shoot(model_campfire(), "campfire", out, 20.0, 1.2, 10.0)
		print("eror klara")
	if which == "all" or which == "trees":
		_setup(256)
		var tsz := {"S": 1.6, "M": 2.0, "L": 2.5}
		for k in tsz:
			await shoot(model_spruce(tsz[k]), "spruce_" + k, out, 34.0, 9.0 * tsz[k] / 2.0)
		for k in ["S", "M"]:
			await shoot(model_pine(tsz[k]), "pine_" + k, out, 32.0, 8.0 * tsz[k] / 2.0)
			await shoot(model_birch(tsz[k]), "birch_" + k, out, 30.0, 6.5 * tsz[k] / 2.0)
			await shoot(model_oak(tsz[k]), "oak_" + k, out, 32.0, 6.5 * tsz[k] / 2.0)
		await shoot(model_bush(), "bush", out, 6.0, 1.0)
		await shoot(model_rock(0), "rock_a", out, 6.0, 0.8)
		await shoot(model_rock(2), "rock_b", out, 6.0, 0.8)
		print("träd klara")
	if which == "all" or which == "people":
		_setup(128)
		var shirts := {"blue": Color("2f6fb5"), "brown": Color("8a5a2b"), "green": Color("4a8a3a"), "orange": Color("d9822b"), "grey": Color("7d838c"), "red": Color("c0392b")}
		for c in shirts:
			for d in 8:
				await shoot(model_person(shirts[c], d * 45.0, -1, 6), "person_%s_%d_idle" % [c, d], out, 2.6, 0.95)
				for f in 6:
					await shoot(model_person(shirts[c], d * 45.0, f, 6), "person_%s_%d_%d" % [c, d, f], out, 2.6, 0.95)
		print("människor klara")
	var fm := FileAccess.open(out + "/meta_%s.json" % which, FileAccess.WRITE)
	fm.store_string(JSON.stringify(meta))
	fm.close()
	quit()
