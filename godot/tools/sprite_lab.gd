extends SceneTree
## Förrenderade isometriska sprites: bygger enkla 3D-modeller med kod, belyser dem och sparar PNG.
## Kör (kräver skärm, t.ex. xvfb):  godot --path godot --rendering-driver opengl3 -s tools/sprite_lab.gd -- --out=/sökväg/mapp

const SIZE := 256
var vp: SubViewport
var holder: Node3D

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
func model_house(wall: Color, roof: Color, w: float = 9.0, d: float = 6.0, h: float = 4.6) -> Node3D:
	var n := Node3D.new()
	var wm := mat(wall, planks(wall), Vector3(w / 2.0, h / 2.0, 1))
	var wm2 := mat(wall, planks(wall), Vector3(d / 2.0, h / 2.0, 1))
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), wm)
	var trim := mat(Color("f1ece0"))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(n, Vector3(sx * (w / 2 - 0.12), h / 2, sz * (d / 2 - 0.12)), Vector3(0.28, h, 0.28), trim)
	box(n, Vector3(0, 0.12, 0), Vector3(w + 0.25, 0.25, d + 0.25), mat(Color("6d6a64")))
	# tak: sadeltak med nock längs x
	var rm := mat(roof, tiles(roof), Vector3(w / 2.0, 2.0, 1), 0.8)
	var rh := 2.6
	var prism := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(d + 1.2, rh, w + 1.0)
	pm.left_to_right = 0.5
	prism.mesh = pm
	prism.material_override = rm
	prism.rotation_degrees = Vector3(0, 90, 0)
	prism.position = Vector3(0, h + rh / 2 - 0.02, 0)
	n.add_child(prism)
	# skorsten
	box(n, Vector3(w * 0.25, h + rh * 0.8, -d * 0.12), Vector3(0.9, 2.0, 0.9), mat(Color("7a3b2d"), plaster(Color("8a4636"))))
	# fönster och dörr (syns på +z och +x)
	var glass := mat(Color(0.22, 0.32, 0.45), null, Vector3.ONE, 0.2)
	var frame := mat(Color("f4f0e6"))
	for i in 3:
		var x := -w * 0.3 + i * (w * 0.3)
		box(n, Vector3(x, h * 0.55, d / 2 + 0.02), Vector3(1.2, 1.4, 0.12), frame)
		box(n, Vector3(x, h * 0.55, d / 2 + 0.08), Vector3(0.9, 1.1, 0.1), glass)
	box(n, Vector3(w / 2 + 0.02, h * 0.55, 0.0), Vector3(0.12, 1.4, 1.2), frame)
	box(n, Vector3(w / 2 + 0.08, h * 0.55, 0.0), Vector3(0.1, 1.1, 0.9), glass)
	box(n, Vector3(w * 0.35, 1.1, d / 2 + 0.05), Vector3(1.1, 2.1, 0.12), mat(Color("4a3220")))
	return n

func model_block(levels: int = 4) -> Node3D:
	var n := Node3D.new()
	var w := 16.0
	var d := 9.0
	var h := 3.0 * levels
	var wall := Color("d6cfb8")
	box(n, Vector3(0, h / 2, 0), Vector3(w, h, d), mat(wall, plaster(wall), Vector3(w / 3.0, h / 3.0, 1)))
	box(n, Vector3(0, h + 0.25, 0), Vector3(w + 0.4, 0.5, d + 0.4), mat(Color("6b6c72")))
	var glass := mat(Color(0.25, 0.36, 0.5), null, Vector3.ONE, 0.15)
	for lv in levels:
		for i in 6:
			var x := -w / 2 + 1.6 + i * 2.8
			box(n, Vector3(x, 1.7 + lv * 3.0, d / 2 + 0.03), Vector3(1.5, 1.5, 0.1), glass)
		for i in 3:
			var z := -d / 2 + 1.4 + i * 3.0
			box(n, Vector3(w / 2 + 0.03, 1.7 + lv * 3.0, z), Vector3(0.1, 1.5, 1.5), glass)
	return n

func model_spruce(s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	cyl(n, Vector3(0, 1.0 * s, 0), 0.28 * s, 2.0 * s, mat(Color("4a3524")))
	for k in 5:
		var m := mat(Color(0.07 + 0.012 * k, 0.22 + 0.025 * k, 0.12 + 0.01 * k))
		cone(n, Vector3(0, (1.6 + k * 1.45) * s, 0), (2.9 - k * 0.5) * s, 2.6 * s, m, 9)
	return n

func model_birch(s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	cyl(n, Vector3(0, 2.6 * s, 0), 0.22 * s, 5.2 * s, mat(Color("e8e4d6")))
	var g := [Color("4a7a26"), Color("5a8a2e"), Color("3f6c20"), Color("6a9a34")]
	var offs := [Vector3(0, 6.2, 0), Vector3(1.2, 5.4, 0.5), Vector3(-1.1, 5.6, -0.6), Vector3(0.2, 7.2, 0.3), Vector3(-0.4, 5.2, 1.2)]
	for i in offs.size():
		ball(n, offs[i] * s, (1.7 - 0.12 * i) * s, mat(g[i % 4]), 0.9)
	return n

func model_person(shirt: Color) -> Node3D:
	var n := Node3D.new()
	box(n, Vector3(0, 1.0, 0), Vector3(0.55, 0.9, 0.3), mat(shirt))
	box(n, Vector3(-0.15, 0.3, 0), Vector3(0.2, 0.6, 0.22), mat(Color("3a3028")))
	box(n, Vector3(0.15, 0.3, 0), Vector3(0.2, 0.6, 0.22), mat(Color("3a3028")))
	ball(n, Vector3(0, 1.72, 0), 0.24, mat(Color("f1c9a0")))
	box(n, Vector3(-0.38, 1.0, 0), Vector3(0.14, 0.7, 0.16), mat(shirt.darkened(0.15)))
	box(n, Vector3(0.38, 1.0, 0), Vector3(0.14, 0.7, 0.16), mat(shirt.darkened(0.15)))
	return n

# ---------- rendering ----------
func _setup() -> void:
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
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(-8, 14, 10), Vector3.ZERO)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 15.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.612, 0.5, 0.612) * 40.0 + Vector3(0, 3.5, 0), Vector3(0, 3.5, 0))
	holder = Node3D.new()
	vp.add_child(holder)

func shoot(node: Node3D, path: String, cam_size: float = 15.0, target_y: float = 3.5) -> void:
	for c in holder.get_children():
		c.queue_free()
	holder.add_child(node)
	var cam: Camera3D = vp.get_child(2)
	cam.size = cam_size
	cam.look_at_from_position(Vector3(0.612, 0.5, 0.612) * 40.0 + Vector3(0, target_y, 0), Vector3(0, target_y, 0))
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(path)

func _initialize() -> void:
	var out := "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_setup()
	var jobs := [
		["house_red", model_house(Color("8c3626"), Color("34343a")), 15.0, 3.5],
		["house_yellow", model_house(Color("c9a64e"), Color("6e3427"), 8.0, 6.5, 4.4), 15.0, 3.5],
		["house_white", model_house(Color("e4dfce"), Color("44444a"), 10.0, 6.0, 4.8), 15.0, 3.5],
		["block", model_block(4), 24.0, 6.0],
		["spruce", model_spruce(1.0), 16.0, 5.5],
		["birch", model_birch(1.0), 16.0, 4.5],
		["person", model_person(Color("2f6fb5")), 3.2, 0.95],
	]
	for j in jobs:
		await shoot(j[1], "%s/%s.png" % [out, j[0]], j[2], j[3])
		print("sprite: ", j[0])
	quit()
