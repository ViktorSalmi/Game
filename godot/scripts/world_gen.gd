extends RefCounted
## Genererar en egen värld ur ett seed. Ger samma fält som MapData (så all rendering/sim kan återanvändas).
## Biomer: 0 sjö/hav, 1 å/vad, 2 sand, 3 gräs/åker, 4 skog, 5 torrt, 6 berg, 8 myr

const MapData = preload("res://scripts/map_data.gd")

static func generate(seed_value: int, size: int = 384):
	var d = MapData.new()
	d.generated = true
	d.map_name = "Egen värld (seed %d)" % seed_value
	d.w = size
	d.h = size
	d.cell_m = 8.0
	d.bbox = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var n_e := FastNoiseLite.new()
	n_e.seed = seed_value
	n_e.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_e.frequency = 0.011
	n_e.fractal_octaves = 5
	var n_e2 := FastNoiseLite.new()
	n_e2.seed = seed_value + 7
	n_e2.frequency = 0.035
	n_e2.fractal_octaves = 3
	var n_m := FastNoiseLite.new()
	n_m.seed = seed_value + 101
	n_m.frequency = 0.014
	n_m.fractal_octaves = 4
	var n_l := FastNoiseLite.new()
	n_l.seed = seed_value + 303
	n_l.frequency = 0.03

	var elev := PackedFloat32Array()
	elev.resize(size * size)
	var biome := PackedByteArray()
	biome.resize(size * size)
	var c := size * 0.5
	for y in size:
		for x in size:
			var nx := (x - c) / c
			var ny := (y - c) / c
			var dist := sqrt(nx * nx + ny * ny)
			var e := 0.5 + n_e.get_noise_2d(x, y) * 0.55 + n_e2.get_noise_2d(x, y) * 0.12
			e -= pow(clampf(dist, 0.0, 1.3), 3.2) * 0.50     # ö: hav vid kanterna
			elev[y * size + x] = e
	for y in size:
		for x in size:
			var e := elev[y * size + x]
			var m := 0.5 + n_m.get_noise_2d(x, y) * 0.7
			var b := 3
			if e < 0.27:
				b = 0
			elif e < 0.30:
				b = 2
			elif e > 0.66:
				b = 6
			elif m > 0.80 and e < 0.47:
				b = 8
			elif m > 0.52:
				b = 4
			elif m < 0.22:
				b = 5
			# småsjöar
			if b != 0 and b != 6 and e > 0.40 and e < 0.60 and n_l.get_noise_2d(x, y) > 0.62:
				b = 0
			biome[y * size + x] = b
	# floder: från höga punkter nedåt tills de når vatten
	var rivers := 0
	var tries := 0
	while rivers < 16 and tries < 900:
		tries += 1
		var sx := rng.randi_range(8, size - 9)
		var sy := rng.randi_range(8, size - 9)
		if elev[sy * size + sx] < 0.50 or biome[sy * size + sx] == 0:
			continue
		var px := sx
		var py := sy
		var path: Array = []
		var seen := {}
		var ok := false
		for step in 1600:
			path.append(Vector2i(px, py))
			seen[py * size + px] = true
			if biome[py * size + px] == 0 and step > 2:
				ok = true
				break
			var best := Vector2i(-1, -1)
			var be := 1e9
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var qx := px + dx
					var qy := py + dy
					if qx < 1 or qy < 1 or qx >= size - 1 or qy >= size - 1 or seen.has(qy * size + qx):
						continue
					var qe := elev[qy * size + qx] + rng.randf() * 0.010
					if qe < be:
						be = qe
						best = Vector2i(qx, qy)
			if best.x < 0:
				break
			px = best.x
			py = best.y
		if ok and path.size() > 30:
			for p in path:
				if biome[p.y * size + p.x] != 0:
					biome[p.y * size + p.x] = 1
			rivers += 1
	d.w = size
	d.h = size
	d.biome = biome
	d.road = PackedByteArray()
	d.road.resize(size * size)
	d.estep = 8
	d.ew = int(ceil(size / 8.0)) + 1
	d.eh = d.ew
	d.elev = PackedFloat32Array()
	d.elev.resize(d.ew * d.eh)
	var lo := 1e9
	var hi := -1e9
	for j in d.eh:
		for i in d.ew:
			var v: float = elev[mini(j * 8, size - 1) * size + mini(i * 8, size - 1)] * 400.0
			d.elev[j * d.ew + i] = v
			lo = minf(lo, v)
			hi = maxf(hi, v)
	d.lo = lo
	d.hi = hi
	d.places = []
	d.pois = []
	d.bld = PackedInt32Array()
	d._stats()
	# grottan: land vid bergets fot, nära vatten och skog, nära kartans mitt
	var best_score := -1e9
	var cave := Vector2i(size / 2, size / 2)
	for t in 6000:
		var x := rng.randi_range(24, size - 25)
		var y := rng.randi_range(24, size - 25)
		var e := elev[y * size + x]
		var b := int(biome[y * size + x])
		if e < 0.50 or e > 0.66 or b == 0 or b == 1 or b == 8:
			continue
		var water := 0
		var forest := 0
		var rock := 0
		var bad := 0
		for dy in range(-12, 13, 3):
			for dx in range(-12, 13, 3):
				var q := int(biome[(y + dy) * size + (x + dx)])
				if q == 0 or q == 1:
					water += 1
				elif q == 4:
					forest += 1
				elif q == 6:
					rock += 1
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var q2 := int(biome[(y + dy) * size + (x + dx)])
				if q2 == 0 or q2 == 1 or q2 == 8:
					bad += 1
		if bad > 0 or water < 2 or forest < 6 or rock < 2:
			continue
		var sc := minf(water, 6.0) * 2.0 + minf(forest, 20.0) + minf(rock, 8.0) - Vector2(x - c, y - c).length() * 0.06
		if sc > best_score:
			best_score = sc
			cave = Vector2i(x, y)
	d.start_cell = cave
	# gör platsen runt grottan till öppen mark (gräs) så första bosättningen får plats
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if dx * dx + dy * dy <= 20:
				var i := (cave.y + dy) * size + (cave.x + dx)
				if biome[i] != 0 and biome[i] != 1:
					biome[i] = 3
	d.biome = biome
	d._stats()
	d.ok = true
	return d
