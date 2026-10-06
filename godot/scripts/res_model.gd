extends RefCounted
## Resurser på kartan (träd, bärbuskar, sten). Deterministiska utifrån biom + hash; uttömda rutor sparas i `taken`.

signal changed(chunk: Vector2i)

const TREE := 1
const BUSH := 2
const ROCK := 3
const AMOUNT := {1: 80, 2: 40, 3: 120}
const REGROW := {1: 2400.0, 2: 500.0, 3: 1e18}
const CS := 32

var data
var taken := {}
var time_ref := 0.0

func setup(d) -> void:
	data = d

func _hash(x: int, y: int) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7) * 43758.5453, 1.0)

func base_kind(x: int, y: int) -> int:
	var b: int = data.biome_at(x, y)
	var h := _hash(x, y)
	match b:
		4:
			if h < 0.40: return TREE
			if h < 0.425: return BUSH
			if h < 0.435: return ROCK
		3:
			if h < 0.025: return TREE
			if h < 0.045: return BUSH
			if h < 0.055: return ROCK
		8:
			if h < 0.06: return TREE
		6:
			if h < 0.22: return ROCK
	return 0

func kind_at(x: int, y: int) -> int:
	var k := base_kind(x, y)
	if k == 0:
		return 0
	var key: int = y * data.w + x
	if taken.has(key):
		var t: Array = taken[key]
		if t[0] <= 0:
			if time_ref >= t[1]:
				taken.erase(key)
				return k
			return 0
	return k

func amount_at(x: int, y: int) -> int:
	var k := kind_at(x, y)
	if k == 0:
		return 0
	var key: int = y * data.w + x
	if taken.has(key):
		return int(taken[key][0])
	return int(AMOUNT[k])

func harvest(x: int, y: int, amt: int) -> int:
	var k := kind_at(x, y)
	if k == 0:
		return 0
	var key: int = y * data.w + x
	var rem: int = int(AMOUNT[k])
	if taken.has(key):
		rem = int(taken[key][0])
	var got := mini(rem, amt)
	rem -= got
	taken[key] = [rem, (time_ref + float(REGROW[k])) if rem <= 0 else 0.0]
	if rem <= 0:
		changed.emit(Vector2i(x / CS, y / CS))
	return got

func clear_area(x0: int, y0: int, w: int, h: int) -> void:
	var dirty := {}
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if base_kind(x, y) != 0:
				taken[y * data.w + x] = [0, 1e18]
				dirty[Vector2i(x / CS, y / CS)] = true
	for c in dirty:
		changed.emit(c)

## Hittar närmaste ruta med resursen (spiral utåt). Returnerar Vector2i(-1,-1) om inget finns.
func find_nearest(kind: int, from: Vector2i, radius: int) -> Vector2i:
	if kind_at(from.x, from.y) == kind:
		return from
	for r in range(1, radius + 1):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				if kind_at(from.x + dx, from.y + dy) == kind:
					return Vector2i(from.x + dx, from.y + dy)
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				if kind_at(from.x + dx, from.y + dy) == kind:
					return Vector2i(from.x + dx, from.y + dy)
	return Vector2i(-1, -1)
