extends Node2D
## Fog of war: 4x4 rutor per pixel, uppskalat med linjär filtrering => mjuka kanter.
## Tillstånd: 0 outforskat (svart), 1 utforskat (dämpat), synligt just nu (genomskinligt).

const Iso = preload("res://scripts/iso.gd")
const CELL := 4

var data
var fw := 0
var fh := 0
var explored := PackedByteArray()
var visible_now := PackedByteArray()
var image: Image
var tex: ImageTexture
var sprite: Sprite2D
var enabled := true
var dirty := true

func setup(map_data) -> void:
	data = map_data
	fw = int(ceil(float(data.w) / CELL)) + 2
	fh = int(ceil(float(data.h) / CELL)) + 2
	explored.resize(fw * fh)
	visible_now.resize(fw * fh)
	image = Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.02, 0.03, 0.05, 0.97))
	tex = ImageTexture.create_from_image(image)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# pixel (i,j) -> ruta (4i,4j): isometrisk matris
	sprite.transform = Transform2D(Vector2(CELL * Iso.TW * 0.5, CELL * Iso.TH * 0.5), Vector2(-CELL * Iso.TW * 0.5, CELL * Iso.TH * 0.5), Vector2.ZERO)
	add_child(sprite)
	z_index = 50

func _idx(i: int, j: int) -> int:
	return j * fw + i

func set_sources(sources: Array) -> void:
	## sources: [{cell:Vector2, r:float}]
	visible_now.fill(0)
	for s in sources:
		var cx := int(s["cell"].x) / CELL
		var cy := int(s["cell"].y) / CELL
		var r: int = int(ceil(float(s["r"]) / CELL))
		for j in range(cy - r, cy + r + 1):
			for i in range(cx - r, cx + r + 1):
				if i < 0 or j < 0 or i >= fw or j >= fh:
					continue
				if (i - cx) * (i - cx) + (j - cy) * (j - cy) <= r * r:
					visible_now[_idx(i, j)] = 1
					explored[_idx(i, j)] = 1
	dirty = true

func reveal_all() -> void:
	explored.fill(1)
	dirty = true

func is_explored(x: float, y: float) -> bool:
	if not enabled:
		return true
	var i := int(x) / CELL
	var j := int(y) / CELL
	if i < 0 or j < 0 or i >= fw or j >= fh:
		return false
	return explored[_idx(i, j)] == 1

func refresh() -> bool:
	if not dirty:
		return false
	dirty = false
	for j in fh:
		for i in fw:
			var k := _idx(i, j)
			var a := 0.0
			if enabled:
				if visible_now[k] == 1:
					a = 0.0
				elif explored[k] == 1:
					a = 0.45
				else:
					a = 0.97
			image.set_pixel(i, j, Color(0.02, 0.03, 0.05, a))
	tex.update(image)
	return true

func toggle() -> void:
	enabled = not enabled
	sprite.visible = enabled
	dirty = true
