extends Node2D
## Etapp 1: isometriska Borås – karta, kamera, fog of war, minikarta, platshållarspejare.

const MapData = preload("res://scripts/map_data.gd")
const Iso = preload("res://scripts/iso.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Fog = preload("res://scripts/fog.gd")
const Pathing = preload("res://scripts/pathing.gd")
const Scout = preload("res://scripts/scout.gd")
const MiniMap = preload("res://scripts/minimap.gd")
const Overlay = preload("res://scripts/overlay.gd")
const Hud = preload("res://scripts/hud.gd")

var data
var terrain
var fog
var pathing
var scout
var minimap
var overlay
var hud
var cam: Camera2D
var home_cell := Vector2(0, 0)
var fog_timer := 0.0
var mini_timer := 0.0
var dragging := false
var frame_no := 0
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	RenderingServer.set_default_clear_color(Color(0.04, 0.055, 0.09))
	var t0 := Time.get_ticks_msec()
	data = MapData.new()
	var found: bool = data.load_any(String(args.get("data", "")))
	print("Karta: %s (%d x %d)  källa=%s  laddad på %d ms" % [data.map_name, data.w, data.h, data.source if found else "DEMO", Time.get_ticks_msec() - t0])

	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup(data)

	fog = Fog.new()
	add_child(fog)
	fog.setup(data)

	var start := Vector2(data.w * 0.5, data.h * 0.5)
	var bp = data.find_place("Borås")
	if bp != null:
		start = Vector2(float(bp["x"]), float(bp["y"]))
	t0 = Time.get_ticks_msec()
	pathing = Pathing.new()
	pathing.setup(data)
	print("Vägnät byggt på %d ms" % (Time.get_ticks_msec() - t0))
	var sc: Vector2i = pathing.nearest_walkable(Vector2i(start))
	home_cell = Vector2(sc) + Vector2(0.5, 0.5)

	scout = Scout.new()
	add_child(scout)
	scout.setup(data, home_cell)
	scout.z_index = 5

	cam = Camera2D.new()
	add_child(cam)
	cam.position = Iso.to_screen(home_cell.x, home_cell.y)
	cam.zoom = Vector2.ONE * float(args.get("zoom", "1.0"))
	cam.make_current()

	var ol := CanvasLayer.new()
	ol.layer = 5
	add_child(ol)
	overlay = Overlay.new()
	ol.add_child(overlay)
	overlay.setup(data, fog, cam)

	hud = Hud.new()
	hud.layer = 10
	add_child(hud)
	hud.build()
	hud.set_legend(data)
	minimap = MiniMap.new()
	hud.minimap_holder.add_child(minimap)
	minimap.setup(data, fog)
	minimap.jump_to.connect(_on_minimap_jump)
	hud.buttons["Karta (M)"].pressed.connect(fit_map)
	hud.buttons["Dimma (F)"].pressed.connect(toggle_fog)
	hud.buttons["Förklaring (L)"].pressed.connect(toggle_legend)

	if args.has("focus"):
		var f: PackedStringArray = String(args["focus"]).split(",")
		cam.position = Iso.to_screen(float(f[0]), float(f[1]))
	if args.has("fit"):
		fit_map()
	if args.has("nofog"):
		fog.toggle()
	if args.has("reveal"):
		fog.reveal_all()
	if args.has("goto"):
		var g: PackedStringArray = String(args["goto"]).split(",")
		scout.command_path(pathing.find_path(Vector2i(scout.cell), Vector2i(int(g[0]), int(g[1]))))
	_update_fog(true)

func _on_minimap_jump(cell: Vector2) -> void:
	cam.position = Iso.to_screen(cell.x, cell.y)

func toggle_fog() -> void:
	fog.toggle()
	minimap.refresh()

func toggle_legend() -> void:
	hud.legend_panel.visible = not hud.legend_panel.visible

func fit_map() -> void:
	var vp := get_viewport_rect().size
	var tw: float = (data.w + data.h) * Iso.TW * 0.5
	var th: float = (data.w + data.h) * Iso.TH * 0.5
	cam.zoom = Vector2.ONE * minf(vp.x / tw, (vp.y - 60.0) / th) * 0.95
	cam.position = Iso.to_screen(data.w * 0.5, data.h * 0.5)
	hud.legend_panel.visible = true

func screen_to_world(sp: Vector2) -> Vector2:
	return cam.position + (sp - get_viewport_rect().size * 0.5) / cam.zoom.x

func view_cells() -> Array:
	var vp := get_viewport_rect().size
	var out: Array = []
	for sp in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]:
		out.append(Iso.to_cell(screen_to_world(sp)))
	return out

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.15, ev.position)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 1.15, ev.position)
		elif ev.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = ev.pressed
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			var c := Iso.to_cell(screen_to_world(ev.position))
			var p: Array[Vector2i] = pathing.find_path(Vector2i(scout.cell), Vector2i(floori(c.x), floori(c.y)))
			scout.command_path(p)
	elif ev is InputEventMouseMotion and dragging:
		cam.position -= ev.relative / cam.zoom.x
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_M: fit_map()
			KEY_F: toggle_fog()
			KEY_L: toggle_legend()
			KEY_HOME: cam.position = scout.position
			KEY_ESCAPE: get_tree().quit()

func _zoom(f: float, mouse: Vector2) -> void:
	var vp := get_viewport_rect().size
	var z0 := cam.zoom.x
	var z1 := clampf(z0 * f, 0.05, 3.0)
	var before := cam.position + (mouse - vp * 0.5) / z0
	cam.zoom = Vector2.ONE * z1
	cam.position = before - (mouse - vp * 0.5) / z1

func _update_fog(force: bool = false) -> void:
	fog.set_sources([{"cell": scout.cell, "r": scout.vision}, {"cell": home_cell, "r": 18.0}])
	if fog.refresh() or force:
		minimap.refresh()

func _process(dt: float) -> void:
	frame_no += 1
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if dir != Vector2.ZERO:
		var boost := 2.2 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		cam.position += dir.normalized() * 900.0 * boost * dt / cam.zoom.x
	cam.position.x = clampf(cam.position.x, -data.h * Iso.TW * 0.5, data.w * Iso.TW * 0.5)
	cam.position.y = clampf(cam.position.y, 0.0, (data.w + data.h) * Iso.TH * 0.5)

	var vc := view_cells()
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for c in vc:
		mn = mn.min(c)
		mx = mx.max(c)
	terrain.update_visible(mn - Vector2(8, 8), mx + Vector2(8, 8))
	minimap.set_view(vc)

	fog_timer += dt
	if fog_timer > 0.15:
		fog_timer = 0.0
		_update_fog()

	var mc := Iso.to_cell(screen_to_world(get_viewport().get_mouse_position()))
	var cx := floori(mc.x)
	var cy := floori(mc.y)
	var b: int = data.biome_at(cx, cy)
	if b == 10 or not fog.is_explored(cx, cy):
		hud.info_label.text = "%s\n%s" % [data.map_name, "Okänt område" if b != 10 else "Utanför kommunen"]
	else:
		var ll: Vector2 = data.latlon(cx + 0.5, cy + 0.5)
		var near: String = data.nearest_place(cx, cy)
		var rd: int = data.road_at(cx, cy)
		hud.info_label.text = "%s%s%s\nHöjd %d m%s\n%.4f°N  %.4f°E" % [data.BIOME_NAMES[b], " · väg" if rd == 1 else (" · järnväg" if rd == 2 else ""), "", int(data.elev_at(cx, cy)), ("  ·  nära " + near) if near != "" else "", ll.x, ll.y]
	hud.fps_label.text = "%d FPS · %d kartbitar" % [Engine.get_frames_per_second(), terrain.chunk_count()]

	if args.has("report") and frame_no == int(args.get("frames", "90")):
		var seen := 0
		for v in fog.explored:
			seen += v
		print("RAPPORT: spejare=%s väg kvar=%d utforskade fogceller=%d/%d kartbitar=%d" % [scout.cell, scout.path.size(), seen, fog.explored.size(), terrain.chunk_count()])
		get_tree().quit()
	if args.has("shot") and frame_no == int(args.get("frames", "90")):
		get_viewport().get_texture().get_image().save_png(String(args["shot"]))
		print("Skärmbild sparad: ", args["shot"])
		get_tree().quit()
