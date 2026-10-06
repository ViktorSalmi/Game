extends RefCounted
## Laddar sprite-atlasen (assets/sprites/atlas.png + atlas.json) och ritar sprites på ett CanvasItem.

const SCALE_AXIS_PX := 35.78    # skärmpixlar längs en isometrisk rutaxel (en ruta)

var ok := false
var tex: ImageTexture
var info := {}

func load_atlas() -> bool:
	var img := Image.load_from_file("res://assets/sprites/atlas.png")
	if img == null or img.is_empty():
		return false
	img.generate_mipmaps()
	tex = ImageTexture.create_from_image(img)
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/atlas.json"))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	info = d["sprites"]
	ok = true
	return true

func has(name: String) -> bool:
	return info.has(name)

func draw(ci: CanvasItem, name: String, pos: Vector2, scale: float, flip: bool = false, mod: Color = Color.WHITE) -> void:
	var s = info.get(name)
	if s == null:
		return
	var w: float = s["w"] * scale
	var h: float = s["h"] * scale
	var src := Rect2(s["x"], s["y"], s["w"], s["h"])
	if flip:
		ci.draw_texture_rect_region(tex, Rect2(pos.x + s["ax"] * scale, pos.y - s["ay"] * scale, -w, h), src, mod)
	else:
		ci.draw_texture_rect_region(tex, Rect2(pos.x - s["ax"] * scale, pos.y - s["ay"] * scale, w, h), src, mod)

## Skala så att en modell med längd model_len (m) täcker real_len_m i spelvärlden (cell_m meter per ruta).
func scale_for_len(name: String, real_len_m: float, cell_m: float) -> float:
	var s = info.get(name)
	if s == null or float(s["len"]) <= 0.0:
		return 0.3
	return (real_len_m / float(s["len"])) * (SCALE_AXIS_PX / cell_m) / (0.79 * float(s["ppm"]))
