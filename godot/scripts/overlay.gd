extends Control
## Ritar ortsnamn och sevärdheter i skärmrymd (konstant textstorlek oavsett zoom).

const Iso = preload("res://scripts/iso.gd")
var data
var fog
var cam: Camera2D

func setup(map_data, fog_node, camera: Camera2D) -> void:
	data = map_data
	fog = fog_node
	cam = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if data == null:
		return
	var font := ThemeDB.fallback_font
	var xf := get_viewport().get_canvas_transform()
	var vp := get_viewport_rect().size
	var z := cam.zoom.x
	for p in data.places:
		var rank := 4
		match String(p["t"]):
			"city": rank = 1
			"town": rank = 2
			"suburb": rank = 3
		if (z < 0.25 and rank > 2) or (z < 0.6 and rank > 3) or (z < 1.0 and rank > 4):
			continue
		var px := float(p["x"])
		var py := float(p["y"])
		if not fog.is_explored(px, py):
			continue
		var sp := xf * Iso.to_screen(px, py)
		if sp.x < -100 or sp.y < -50 or sp.x > vp.x + 100 or sp.y > vp.y + 50:
			continue
		var fs := 17 if rank == 1 else (14 if rank == 2 else 12)
		var text := String(p["n"])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_circle(sp, 4.0 if rank == 1 else 3.0, Color("e5484d"))
		draw_string_outline(font, sp + Vector2(-w * 0.5, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
		draw_string(font, sp + Vector2(-w * 0.5, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	for q in data.pois:
		var qx := float(q["x"])
		var qy := float(q["y"])
		if not fog.is_explored(qx, qy):
			continue
		var sp := xf * Iso.to_screen(qx + 0.5, qy + 0.5)
		if sp.x < -50 or sp.y < -50 or sp.x > vp.x + 50 or sp.y > vp.y + 50:
			continue
		var d := PackedVector2Array([sp + Vector2(0, -6), sp + Vector2(5, 0), sp + Vector2(0, 6), sp + Vector2(-5, 0)])
		draw_colored_polygon(d, Color("ffd45a"))
		draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), Color.BLACK, 1.5)
		if z >= 0.8:
			var t := String(q["n"])
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string_outline(font, sp + Vector2(-tw * 0.5, -10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.85))
			draw_string(font, sp + Vector2(-tw * 0.5, -10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffd45a"))
