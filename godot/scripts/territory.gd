extends Node2D
## Stadsområden: varje stad får ett område som växer med invånarantalet. Ritas som ett lager med gränser.

const Iso = preload("res://scripts/iso.gd")

var data
var sim
var ids := PackedByteArray()
var best := PackedFloat32Array()
var img: Image
var tex: ImageTexture
var sprite: Sprite2D
var sig := ""
var enabled := true

func setup(map_data, sim_ref) -> void:
	data = map_data
	sim = sim_ref
	ids.resize(data.w * data.h)
	best.resize(data.w * data.h)
	img = Image.create(data.w, data.h, false, Image.FORMAT_R8)
	tex = ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/territory.gdshader")
	mat.set_shader_parameter("ids", tex)
	mat.set_shader_parameter("map_size", Vector2(data.w, data.h))
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.material = mat
	sprite.transform = Transform2D(Iso.to_screen(1, 0), Iso.to_screen(0, 1), Vector2.ZERO)
	add_child(sprite)
	z_index = 1

func radius_of(pop: int) -> float:
	return (70.0 + 22.0 * sqrt(float(pop))) / data.cell_m

func refresh() -> void:
	var s := ""
	for t in sim.towns:
		s += "%d:%d;" % [t["hall"], int(t["pop"] / 3)]
	if s == sig:
		return
	sig = s
	ids.fill(0)
	best.fill(1e9)
	var ti := 0
	for t in sim.towns:
		ti += 1
		var hb = sim.building_by_id(t["hall"])
		if hb == null or not hb.done:
			continue
		var c: Vector2 = hb.center()
		var r := radius_of(int(t["pop"]))
		var x0 := maxi(0, int(c.x - r))
		var x1 := mini(data.w - 1, int(c.x + r))
		var y0 := maxi(0, int(c.y - r))
		var y1 := mini(data.h - 1, int(c.y + r))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var d := Vector2(x + 0.5 - c.x, y + 0.5 - c.y).length()
				if d > r:
					continue
				var i: int = y * data.w + x
				var b: int = data.biome[i]
				if b == 0 or b == 10:
					continue
				var score := d / r
				if score < best[i]:
					best[i] = score
					ids[i] = ti
	img.set_data(data.w, data.h, false, Image.FORMAT_R8, ids)
	tex.update(img)

func toggle() -> void:
	enabled = not enabled
	visible = enabled
