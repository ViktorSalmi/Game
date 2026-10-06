extends Control
## Diamantformad minikarta (som i AoE). Visar bara utforskade delar. Klick/drag flyttar kameran.

const Iso = preload("res://scripts/iso.gd")
const PALC := {
	0: Color("1f5d9c"), 1: Color("55a9db"), 2: Color("e0cf94"), 3: Color("79b24b"), 4: Color("386e34"),
	5: Color("cdb06a"), 6: Color("8f8a7c"), 7: Color("f4f7fa"), 8: Color("7f9f7d"), 9: Color("c9c3b8"),
}
signal jump_to(cell: Vector2)

var data
var fog
var img: Image
var tex: ImageTexture
var base_colors := PackedColorArray()
var fw := 0
var fh := 0
var view_cells: Array = []
var kx := 1.0
var ky := 0.5
var origin := Vector2.ZERO

func setup(map_data, fog_node) -> void:
	data = map_data
	fog = fog_node
	fw = fog.fw
	fh = fog.fh
	base_colors.resize(fw * fh)
	for j in fh:
		for i in fw:
			var b: int = data.biome_at(i * 4 + 2, j * 4 + 2)
			var r: int = data.road_at(i * 4 + 2, j * 4 + 2)
			var c: Color = Color(0.04, 0.05, 0.08) if b == 10 else PALC.get(b, Color.MAGENTA)
			base_colors[j * fw + i] = c
	img = Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	tex = ImageTexture.create_from_image(img)
	custom_minimum_size = Vector2(230, 120)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	refresh()

func _layout() -> void:
	kx = size.x / float(fw + fh)
	ky = kx * 0.5
	origin = Vector2(fh * kx, 0)

func refresh() -> void:
	for j in fh:
		for i in fw:
			var k := j * fw + i
			var c := Color(0, 0, 0, 1)
			if fog.is_explored(i * 4 + 2, j * 4 + 2) or not fog.enabled:
				c = base_colors[k]
				if fog.enabled and fog.visible_now[k] == 0:
					c = c.darkened(0.25)
			img.set_pixel(i, j, c)
	tex.update(img)
	queue_redraw()

func _cell_to_local(cell: Vector2) -> Vector2:
	var i := cell.x / 4.0
	var j := cell.y / 4.0
	return origin + Vector2((i - j) * kx, (i + j) * ky)

func set_view(cells: Array) -> void:
	view_cells = cells
	queue_redraw()

func _draw() -> void:
	draw_set_transform_matrix(Transform2D(Vector2(kx, ky), Vector2(-kx, ky), origin))
	draw_texture_rect(tex, Rect2(0, 0, fw, fh), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for p in data.places:
		if String(p["t"]) in ["city", "town"] and fog.is_explored(float(p["x"]), float(p["y"])):
			draw_circle(_cell_to_local(Vector2(float(p["x"]), float(p["y"]))), 2.2, Color("ff5a5f"))
	if view_cells.size() == 4:
		var pts := PackedVector2Array()
		for c in view_cells:
			pts.append(_cell_to_local(c))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.9), 1.5)

func _gui_input(ev: InputEvent) -> void:
	var pressed := false
	var pos := Vector2.ZERO
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
		pos = ev.position
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pressed = true
		pos = ev.position
	if not pressed:
		return
	var a := (pos.x - origin.x) / kx
	var b := (pos.y - origin.y) / ky
	jump_to.emit(Vector2((a + b) * 0.5 * 4.0, (b - a) * 0.5 * 4.0))
	accept_event()
