extends Node2D
## Etapp 1: isometriska Borås – karta, kamera, fog of war, minikarta, platshållarspejare.

const MapData = preload("res://scripts/map_data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Iso = preload("res://scripts/iso.gd")
const Terrain = preload("res://scripts/terrain.gd")
const ResModel = preload("res://scripts/res_model.gd")
const Sprites = preload("res://scripts/sprites.gd")
const Sim = preload("res://scripts/sim.gd")
const Entities = preload("res://scripts/entities.gd")
const Fog = preload("res://scripts/fog.gd")
const Pathing = preload("res://scripts/pathing.gd")
const Scout = preload("res://scripts/scout.gd")
const MiniMap = preload("res://scripts/minimap.gd")
const Overlay = preload("res://scripts/overlay.gd")
const Hud = preload("res://scripts/hud.gd")

var data
var terrain
var resmodel
var sprites
var sim
var entities
var speed := 1.0
var paused := false
var sim_acc := 0.0
var selected = null
var hud_timer := 0.0
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
	var tint := CanvasModulate.new()
	tint.color = Color(1.0, 0.985, 0.95)
	add_child(tint)
	var t0 := Time.get_ticks_msec()
	var found := true
	if args.has("boras") or args.has("data"):
		data = MapData.new()
		found = data.load_any(String(args.get("data", "")))
	else:
		data = WorldGen.generate(int(args.get("seed", "1621")), int(args.get("size", "384")))
	print("Karta: %s (%d x %d)  källa=%s  skapad på %d ms" % [data.map_name, data.w, data.h, data.source if found else "DEMO", Time.get_ticks_msec() - t0])

	resmodel = ResModel.new()
	resmodel.setup(data)
	terrain = Terrain.new()
	add_child(terrain)
	sprites = Sprites.new()
	print("Sprites: ", sprites.load_atlas(), " (", sprites.info.size(), ")")
	terrain.setup(data, resmodel, sprites)

	fog = Fog.new()
	add_child(fog)
	fog.setup(data)

	var start := Vector2(data.w * 0.5, data.h * 0.5)
	var bp = data.find_place("Borås")
	if data.start_cell.x >= 0:
		start = Vector2(data.start_cell)
	elif bp != null:
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

	var first_name := "Borås" if data.find_place("Borås") != null else "Grottbyn"
	sim = Sim.new()
	sim.setup(data, pathing, Vector2i(home_cell), first_name, int(args.get("seed", "1621")))
	scout.visible = false
	entities = Entities.new()
	entities.sim = sim
	entities.sprites = sprites
	entities.data = data
	entities.scout = scout
	entities.z_index = 2
	add_child(entities)

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
	minimap.sim = sim
	hud.minimap_holder.add_child(minimap)
	minimap.setup(data, fog)
	minimap.jump_to.connect(_on_minimap_jump)
	sim.log_event.connect(func(t, imp): hud.add_log(t, imp))
	hud.add_log("Stammen vaknar i %s. Fem personer, ingenting annat." % first_name, true)
	for k in hud.speed_buttons:
		hud.speed_buttons[k].pressed.connect(func(): _set_speed(k))
	hud.buttons["Karta"].pressed.connect(fit_map)
	hud.buttons["Dimma"].pressed.connect(toggle_fog)
	hud.buttons["Info"].pressed.connect(toggle_legend)

	speed = float(args.get("speed", "1"))
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

func _set_speed(label: String) -> void:
	if label == "Paus":
		paused = not paused
	else:
		paused = false
		speed = float(label.trim_suffix("×"))

func job_text(p) -> String:
	var t: String = p.job.get("type", "")
	match t:
		"build": return "Bygger"
		"farm": return "Odlar"
		"gather": return {"wood": "Fällerträd", "stone": "Bryter sten", "food": "Samlar bär"}.get(String(p.job.get("kind", "")), "Samlar")
		"haul": return "Bär hem varor"
		"eat": return "Äter"
		"sleep": return "Sover"
		"wander": return "Strosar"
	return "Vilar" if p.state == "idle" else "På väg"

func select_at(c: Vector2) -> void:
	selected = null
	var bd := 1.3
	for p in sim.people:
		var d: float = p.cell.distance_to(c)
		if d < bd:
			bd = d
			selected = p
	if selected == null:
		for b in sim.buildings:
			if b.contains(c):
				selected = b
				break
	entities.selected = selected

func selection_text() -> String:
	if selected == null:
		return ""
	if selected in sim.people:
		var p = selected
		return "%s\n%d år · %s\nMat %d · Energi %d · Hälsa %d\nBär: %s" % [p.pname, int(sim.age_years(p)), job_text(p), int(p.hunger), int(p.energy), int(p.hp), ("%d %s" % [p.carry_amt, p.carry_kind]) if p.carry_amt > 0 else "ingenting"]
	if selected in sim.buildings:
		var b = selected
		var label: String = sim.SPEC[b.kind]["label"]
		var st := "färdig" if b.done else "byggs %d %%" % int(100.0 * b.progress / b.need)
		var extra := ""
		if b.kind == "house":
			extra = "\nInvånare %d/%d" % [b.residents.size(), 4 + sim.era]
		elif b.kind == "farm":
			extra = "\nBönder %d/5" % b.workers
		return "%s (%s)%s" % [label, st, extra]
	return ""

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
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			select_at(Iso.to_cell(screen_to_world(ev.position)))
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
			KEY_SPACE: _set_speed("Paus")
			KEY_1: _set_speed("1×")
			KEY_2: _set_speed("2×")
			KEY_3: _set_speed("4×")
			KEY_4: _set_speed("8×")
			KEY_5: _set_speed("16×")
			KEY_ESCAPE: get_tree().quit()

func _zoom(f: float, mouse: Vector2) -> void:
	var vp := get_viewport_rect().size
	var z0 := cam.zoom.x
	var z1 := clampf(z0 * f, 0.05, 3.0)
	var before := cam.position + (mouse - vp * 0.5) / z0
	cam.zoom = Vector2.ONE * z1
	cam.position = before - (mouse - vp * 0.5) / z1

func _update_fog(force: bool = false) -> void:
	var src: Array = [{"cell": scout.cell, "r": scout.vision}, {"cell": home_cell, "r": 14.0}]
	for b in sim.buildings:
		if b.done:
			src.append({"cell": b.center(), "r": 16.0 if b.kind == "hall" else 8.0})
	for p in sim.people:
		src.append({"cell": p.cell, "r": 5.0})
	fog.set_sources(src)
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

	if not paused:
		sim_acc += dt * speed
		var steps := 0
		while sim_acc >= 0.1 and steps < 48:
			sim.step(0.1)
			sim_acc -= 0.1
			steps += 1
		if steps >= 48:
			sim_acc = 0.0
	hud_timer += dt
	if hud_timer > 0.2:
		hud_timer = 0.0
		hud.res_label.text = "Trä %d   Mat %d   Guld %d   Sten %d   Befolkning %d/%d" % [sim.stock["wood"], sim.stock["food"], sim.stock["gold"], sim.stock["stone"], sim.pop(), sim.housing_cap()]
		hud.era_label.text = "%s · %s" % [sim.ERA_NAMES[sim.era], sim.date_text()]
		var st := selection_text()
		hud.sel_panel.visible = st != ""
		hud.sel_label.text = st
	var vc := view_cells()
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for c in vc:
		mn = mn.min(c)
		mx = mx.max(c)
	terrain.objects.visible = cam.zoom.x >= 0.3
	terrain.update_visible(mn - Vector2(8, 8), mx + Vector2(8, 8))
	minimap.set_view(vc)
	entities.view_min = mn
	entities.view_max = mx

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
		var pos_txt := ("%.4f°N  %.4f°E" % [ll.x, ll.y]) if data.bbox.size() >= 4 else ("ruta %d, %d" % [cx, cy])
		var near: String = data.nearest_place(cx, cy)
		var rd: int = data.road_at(cx, cy)
		hud.info_label.text = "%s%s%s\nHöjd %d m%s\n%s" % [data.BIOME_NAMES[b], (" · järnväg" if rd == 2 else (" · väg" if rd != 0 else "")), "", int(data.elev_at(cx, cy)), ("  ·  nära " + near) if near != "" else "", pos_txt]
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
