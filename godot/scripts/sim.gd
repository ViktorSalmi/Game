extends RefCounted
## Simuleringen (ingen grafik): människor med behov, arbete, stadsplanering, teknik, eror, kolonisering.

signal log_event(text: String, important: bool)
signal road_changed(chunks: Array)

const Person = preload("res://scripts/person.gd")
const Building = preload("res://scripts/building.gd")
const ResModel = preload("res://scripts/res_model.gd")

const YEAR := 120.0              # spelsekunder per år
const START_YEAR := 1621
const ADULT := 6.0               # år
const MAX_PEOPLE := 1600

const ERA_NAMES := ["Mörka åldern", "Feudala åldern", "Slottsåldern", "Imperieåldern", "Industriella åldern", "Moderna åldern", "Informationsåldern"]
const ERA_YEAR := [0, 1650, 1730, 1810, 1880, 1940, 2010]   # tidigaste år för varje tidsålder
const ERA_TECH := [0, 60, 220, 520, 1100, 2200, 4200]
const ERA_POP := [0, 22, 60, 130, 260, 500, 900]
const ERA_GOLD := [0, 80, 250, 600, 1200, 2500, 4500]
const HOUSE_CAP := [4, 5, 6, 8, 12, 18, 24]
const FARM_MULT := [1.0, 1.15, 1.3, 1.5, 2.0, 2.6, 3.2]

const SPEC := {
	"hall": {"size": 3, "need": 70.0, "cost": {}, "label": "Stadshus"},
	"cave": {"size": 3, "need": 1.0, "cost": {}, "label": "Grotta (urhem)"},
	"house": {"size": 2, "need": 22.0, "cost": {"wood": 30}, "label": "Hus"},
	"farm": {"size": 3, "need": 26.0, "cost": {"wood": 60}, "label": "Åker"},
	"camp": {"size": 2, "need": 20.0, "cost": {"wood": 60}, "label": "Läger"},
	"block": {"size": 3, "need": 45.0, "cost": {"wood": 50, "stone": 80, "gold": 40}, "label": "Flerbostadshus"},
	"factory": {"size": 3, "need": 40.0, "cost": {"wood": 70, "stone": 60, "gold": 80}, "label": "Fabrik", "slots": 8},
	"school": {"size": 3, "need": 35.0, "cost": {"wood": 60, "stone": 40}, "label": "Skola", "slots": 3},
	"market": {"size": 3, "need": 25.0, "cost": {"wood": 50, "gold": 30}, "label": "Marknad", "slots": 3},
	"church": {"size": 3, "need": 40.0, "cost": {"wood": 40, "stone": 80}, "label": "Kyrka"},
}
const LEVEL_NAMES := ["Läger", "By", "Stad", "Storstad", "Metropol"]
const LEVEL_T := [0, 10, 30, 80, 200]
const MALE := ["Anders", "Bengt", "Carl", "Erik", "Gustav", "Hans", "Ivar", "Jon", "Lars", "Magnus", "Nils", "Olof", "Per", "Sven", "Axel", "Knut"]
const FEMALE := ["Anna", "Brita", "Cecilia", "Elin", "Gunilla", "Ingrid", "Karin", "Lena", "Maria", "Sara", "Ulla", "Astrid", "Britta", "Disa", "Freja", "Greta"]
const GEN_A := ["Björk", "Ek", "Havs", "Sol", "Järn", "Dal", "Strand", "Fjäll", "Skog", "Mo", "Lund", "Vind"]
const GEN_B := ["by", "torp", "hamn", "stad", "vik", "ås", "näs", "holm", "fors", "berg"]

var data
var pathing
var res
var rng := RandomNumberGenerator.new()
var time := 0.0
var stock := {"wood": 200, "food": 200, "gold": 100, "stone": 200}
var tech := 0.0
var era := 0
var people: Array = []
var buildings: Array = []
var bmap := {}
var towns: Array = []
var occupied := PackedByteArray()
var next_id := 1
var used_places := {}
var kind_fail := {}
var acc_eco := 0.0
var acc_ai := 0.0
var acc_era := 0.0
var acc_col := 0.0
var deaths := 0
var births := 0

func setup(map_data, path_grid, start: Vector2i, town_name: String, seed_value: int = 1621, res_model = null) -> void:
	data = map_data
	pathing = path_grid
	rng.seed = seed_value
	if res_model != null:
		res = res_model
	else:
		res = ResModel.new()
		res.setup(data)
	occupied.resize(data.w * data.h)
	var hall
	if data.generated:
		add_building("cave", start - Vector2i(1, 1), true)
		var hs := find_site(Vector2(start), 3, 4, 8)
		if hs.x < 0:
			hs = start + Vector2i(5, -1)
		hall = add_building("hall", hs, true)
	else:
		hall = add_building("hall", start - Vector2i(1, 1), true)
	used_places[town_name] = true
	towns.append({"name": town_name, "hall": hall.id, "pop": 0, "level": 0})
	hall.town = 0
	if data.generated:
		carve_road(Vector2i(start), Vector2i(hall.center()))
	for i in 5:
		spawn_person(hall.center() + Vector2(rng.randf_range(-2, 2), 2.5), 20.0 + rng.randf_range(0, 15))

# ---------- hjälp ----------
func year() -> int:
	return START_YEAR + int(time / YEAR)

func date_text() -> String:
	var d := int(fmod(time, YEAR) / YEAR * 360.0)
	return "År %d · dag %d" % [year(), d + 1]

func age_years(p) -> float:
	return (time - p.born) / YEAR

func is_adult(p) -> bool:
	return age_years(p) >= ADULT

func building_by_id(id: int):
	return bmap.get(id)

func count_kind(kind: String, only_done: bool = true) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind and (b.done or not only_done):
			n += 1
	return n

func adults_count() -> int:
	var n := 0
	for p in people:
		if is_adult(p):
			n += 1
	return n

func cap_of(b) -> int:
	match b.kind:
		"house": return HOUSE_CAP[era]
		"block": return 30 + 4 * maxi(0, era - 4)
		"hall": return 6
		"cave": return 6
		"church": return 4
	return 0

func housing_cap() -> int:
	var n := 0
	for b in buildings:
		if b.done:
			n += cap_of(b)
	return n

func pop() -> int:
	return people.size()

func cost_of(kind: String) -> Dictionary:
	var c: Dictionary = SPEC[kind]["cost"].duplicate()
	if kind == "house" and era >= 3:
		c = {"wood": 20, "stone": 15}
	return c

func can_afford(c: Dictionary) -> bool:
	for k in c:
		if stock[k] < c[k]:
			return false
	return true

func pay(c: Dictionary) -> void:
	for k in c:
		stock[k] -= c[k]

func spawn_person(c: Vector2, age: float) -> Object:
	var p := Person.new()
	p.id = next_id
	next_id += 1
	p.female = rng.randf() < 0.5
	p.pname = String(pick(FEMALE) if p.female else pick(MALE))
	p.born = time - age * YEAR
	p.lifespan = rng.randf_range(52.0, 78.0) * (1.0 + 0.07 * era) * YEAR
	p.cell = c
	p.hunger = rng.randf_range(65, 95)
	p.energy = rng.randf_range(60, 95)
	people.append(p)
	return p

func pick(a: Array) -> Variant:
	return a[rng.randi() % a.size()]

func nearest_building(kinds: Array, from: Vector2):
	var best = null
	var bd := 1e18
	for b in buildings:
		if b.done and b.kind in kinds:
			var d: float = from.distance_squared_to(b.center())
			if d < bd:
				bd = d
				best = b
	return best

func town_of(c: Vector2) -> int:
	var best := 0
	var bd := 1e18
	for i in towns.size():
		var h = bmap.get(towns[i]["hall"])
		if h != null and h.done:
			var d: float = c.distance_squared_to(h.center())
			if d < bd:
				bd = d
				best = i
	return best

# ---------- byggnader ----------
func can_place(c: Vector2i, size: int, gap: int = 1) -> bool:
	for y in range(c.y - gap, c.y + size + gap):
		for x in range(c.x - gap, c.x + size + gap):
			if x < 0 or y < 0 or x >= data.w or y >= data.h:
				return false
			if occupied[y * data.w + x] != 0:
				return false
	for y in range(c.y, c.y + size):
		for x in range(c.x, c.x + size):
			var b: int = data.biome_at(x, y)
			if b == 0 or b == 1 or b == 7 or b == 10:
				return false
			if data.road_at(x, y) != 0:
				return false
	return true

func add_building(kind: String, c: Vector2i, done: bool):
	var b := Building.new()
	var sp: Dictionary = SPEC[kind]
	b.id = next_id
	next_id += 1
	b.kind = kind
	b.cell = c
	b.size = int(sp["size"])
	b.need = float(sp["need"])
	b.done = done
	b.progress = b.need if done else 0.0
	for y in range(c.y, c.y + b.size):
		for x in range(c.x, c.x + b.size):
			occupied[y * data.w + x] = 1
	res.clear_area(c.x, c.y, b.size, b.size)
	buildings.append(b)
	bmap[b.id] = b
	if not towns.is_empty():
		b.town = town_of(b.center())
	return b

func find_site(anchor: Vector2, size: int, rmin: int, rmax: int, gap: int = 1) -> Vector2i:
	for r in range(rmin, rmax + 1):
		for attempt in 16:
			var a := rng.randf() * TAU
			var c := Vector2i(int(anchor.x + cos(a) * r) - size / 2, int(anchor.y + sin(a) * r) - size / 2)
			if can_place(c, size, gap):
				return c
	return Vector2i(-1, -1)

## Tomt för hus/åker/service: växer utåt ringvis runt ett stadshus, med luft som minskar med tiden.
func plan_site(hall, size: int, farm: bool) -> Vector2i:
	var near := 0
	for b in buildings:
		if b.center().distance_to(hall.center()) < 30.0:
			near += 1
	var rmin: int = 4 + int(sqrt(float(near)) * 1.3) + (4 if farm else 0)
	var gap := 2 if era < 3 else 1
	var best := Vector2i(-1, -1)
	var bs := 1e9
	var found := 0
	for r in range(rmin, rmin + 12):
		for attempt in 10:
			var a := rng.randf() * TAU
			var c := Vector2i(int(hall.center().x + cos(a) * r) - size / 2, int(hall.center().y + sin(a) * r) - size / 2)
			if can_place(c, size, gap):
				var score := Vector2(c).distance_to(hall.center()) + rng.randf() * 4.0
				if score < bs:
					bs = score
					best = c
				found += 1
		if found >= 6:
			break
	return best

func complete_building(b) -> void:
	b.done = true
	b.progress = b.need
	if b.kind == "hall" and not towns.any(func(t): return t["hall"] == b.id):
		var nm := name_for_town(b.center())
		towns.append({"name": nm, "hall": b.id, "pop": 0, "level": 0})
		b.town = towns.size() - 1
		log_event.emit("🏘 %s grundad!" % nm, true)
		var src = nearest_other_hall(b)
		if src != null:
			carve_road(Vector2i(b.center()), Vector2i(src.center()))
	else:
		var h = nearest_building(["hall"], b.center())
		if h != null:
			carve_road(Vector2i(b.center()), Vector2i(h.center()))
		if b.kind == "school" or b.kind == "factory" or b.kind == "market" or b.kind == "church":
			log_event.emit("%s byggd i %s" % [SPEC[b.kind]["label"], towns[b.town]["name"]], false)

func nearest_other_hall(b):
	var best = null
	var bd := 1e18
	for h in buildings:
		if h.kind == "hall" and h.done and h != b:
			var d: float = b.center().distance_squared_to(h.center())
			if d < bd:
				bd = d
				best = h
	return best

func road_class() -> int:
	return 4 if era < 3 else 1

## Stig/väg mellan två punkter; klassen uppgraderas med tiden.
func carve_road(from_c: Vector2i, to_c: Vector2i) -> void:
	var path: Array[Vector2i] = pathing.find_path(from_c, to_c)
	if path.size() < 2 or path.size() > 90:
		return
	var dirty := {}
	var rc := road_class()
	for c in path:
		var i: int = c.y * data.w + c.x
		if occupied[i] == 0 and data.road[i] == 0 and data.biome[i] != 0 and data.biome[i] != 1:
			data.road[i] = rc
			dirty[Vector2i(c.x / 32, c.y / 32)] = true
	if not dirty.is_empty():
		road_changed.emit(dirty.keys())

func upgrade_roads() -> void:
	var dirty := {}
	for i in data.road.size():
		if data.road[i] == 4:
			data.road[i] = 1
			dirty[Vector2i((i % data.w) / 32, (i / data.w) / 32)] = true
	if not dirty.is_empty():
		road_changed.emit(dirty.keys())

func name_for_town(c: Vector2) -> String:
	var best := ""
	var bd := 45.0
	for p in data.places:
		var nm := String(p["n"])
		if used_places.has(nm):
			continue
		var d := Vector2(float(p["x"]), float(p["y"])).distance_to(c)
		if d < bd:
			bd = d
			best = nm
	if best == "":
		for tries in 30:
			best = String(pick(GEN_A)) + String(pick(GEN_B))
			if not used_places.has(best):
				break
	used_places[best] = true
	return best

# ---------- resurser / roller ----------
func kind_code(kind: String) -> int:
	return {"wood": ResModel.TREE, "food": ResModel.BUSH, "stone": ResModel.ROCK}[kind]

func pick_gather_kind() -> String:
	var farms := count_kind("farm")
	var wood_t := 260.0 + 80.0 * era
	var stone_t := 140.0 + 90.0 * era
	var w := {
		"wood": 0.0 if stock["wood"] > wood_t * 3.0 else maxf(0.12, (wood_t - stock["wood"]) / wood_t + 0.3),
		"stone": maxf(0.0, (stone_t - stock["stone"]) / stone_t) * 0.9,
		"food": maxf(0.0, (people.size() * 8.0 + 120.0 - stock["food"]) / 220.0) * (1.0 if farms == 0 else 0.4),
	}
	var total := 0.0
	for k in w:
		if kind_fail.has(k) and time < kind_fail[k]:
			w[k] = 0.0
		total += w[k]
	if total <= 0.0:
		return ""
	var r := rng.randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "wood"

# ---------- jobb ----------
func go(p, target: Vector2i) -> bool:
	var path: Array[Vector2i] = pathing.find_path(Vector2i(p.cell), target)
	if path.is_empty():
		return false
	if path[0] == Vector2i(p.cell) and path.size() > 1:
		path.pop_front()
	p.path = path
	p.state = "move"
	return true

func end_job(p) -> void:
	var t: String = p.job.get("type", "")
	if t == "farm" or t == "work":
		var b = building_by_id(int(p.job["bid"]))
		if b != null:
			b.workers = maxi(0, b.workers - 1)
	elif t == "build":
		var b = building_by_id(int(p.job["bid"]))
		if b != null:
			b.builders = maxi(0, b.builders - 1)
	p.job = {}
	p.path.clear()
	if p.state != "sleep":
		p.state = "idle"

func begin(p, job: Dictionary, target: Vector2i) -> bool:
	p.job = job
	p.role = String(job.get("type", ""))
	if not go(p, target):
		p.job = {}
		p.state = "idle"
		p.wait = 2.0
		return false
	return true

func start_eat(p) -> bool:
	if stock["food"] >= 3:
		var h = nearest_building(["hall"], p.cell)
		if h != null:
			return begin(p, {"type": "eat", "dur": 2.0}, Vector2i(h.center()))
	var from := Vector2i(p.cell)
	var bush: Vector2i = res.find_nearest(ResModel.BUSH, from, 22)
	if bush.x >= 0:
		return begin(p, {"type": "gather", "kind": "food", "target": bush, "dur": 2.0, "eat": true}, bush)
	return false

func assign_home(p):
	var b = building_by_id(p.home)
	if b != null and b.done:
		return b
	var best = null
	var bd := 1e18
	for h in buildings:
		if (h.kind == "house" or h.kind == "block") and h.done and h.residents.size() < cap_of(h):
			var d: float = p.cell.distance_squared_to(h.center())
			if d < bd:
				bd = d
				best = h
	if best != null:
		best.residents.append(p.id)
		p.home = best.id
	return best

func start_sleep(p) -> bool:
	var h = assign_home(p)
	if h == null:
		h = nearest_building(["hall"], p.cell)
	if h == null:
		return false
	return begin(p, {"type": "sleep", "target": Vector2i(h.center()), "house": h.kind == "house" or h.kind == "block"}, Vector2i(h.center()))

func start_haul(p) -> bool:
	var kinds := ["hall"] if p.carry_kind == "food" else ["hall", "camp"]
	var d = nearest_building(kinds, p.cell)
	if d == null:
		return false
	return begin(p, {"type": "haul", "dur": 1.0}, Vector2i(d.center()))

func start_build(p) -> bool:
	var best = null
	var bd := 1e18
	for b in buildings:
		if not b.done and b.builders < 3:
			var d: float = p.cell.distance_squared_to(b.center())
			if d < bd:
				bd = d
				best = b
	if best == null:
		return false
	best.builders += 1
	if begin(p, {"type": "build", "bid": best.id}, Vector2i(best.center())):
		return true
	best.builders -= 1
	return false

func start_farm(p) -> bool:
	var best = null
	var bd := 1e18
	for b in buildings:
		if b.kind == "farm" and b.done and b.workers < 5:
			var d: float = p.cell.distance_squared_to(b.center())
			if d < bd:
				bd = d
				best = b
	if best == null:
		return false
	best.workers += 1
	if begin(p, {"type": "farm", "bid": best.id, "dur": 30.0}, Vector2i(best.center())):
		return true
	best.workers -= 1
	return false

func start_work(p) -> bool:
	var best = null
	var bd := 1e18
	for b in buildings:
		if b.done and SPEC[b.kind].has("slots") and b.workers < int(SPEC[b.kind]["slots"]):
			var d: float = p.cell.distance_squared_to(b.center())
			if d < bd:
				bd = d
				best = b
	if best == null:
		return false
	best.workers += 1
	if begin(p, {"type": "work", "bid": best.id, "dur": 30.0}, Vector2i(best.center())):
		return true
	best.workers -= 1
	return false

func start_gather(p, kind: String) -> bool:
	if kind == "":
		return false
	var code := kind_code(kind)
	var from := Vector2i(p.cell)
	var t: Vector2i = res.find_nearest(code, from, 6)
	if t.x < 0:
		var d = nearest_building(["hall", "camp"], p.cell)
		if d != null:
			t = res.find_nearest(code, Vector2i(d.center()), 28)
	if t.x < 0:
		kind_fail[kind] = time + 25.0
		return false
	return begin(p, {"type": "gather", "kind": kind, "target": t, "dur": 3.0 / (1.0 + 0.1 * era)}, t)

func builders_needed() -> bool:
	var n := 0
	var open := 0
	for b in buildings:
		if not b.done:
			n += b.builders
			open += 1
	return open > 0 and n < maxi(2, people.size() / 3)

func think(p) -> void:
	p.wait = rng.randf_range(0.2, 1.0)
	if not is_adult(p):
		p.state = "idle"
		if p.hunger < 40:
			start_eat(p)
		elif rng.randf() < 0.3:
			var h = nearest_building(["hall"], p.cell)
			if h != null:
				begin(p, {"type": "wander"}, Vector2i(h.center() + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))))
		p.wait = rng.randf_range(2.0, 6.0)
		return
	if p.hunger < 40 and start_eat(p):
		return
	if p.energy < 30 and start_sleep(p):
		return
	if p.carry_amt >= 20 or (p.carry_amt > 0 and rng.randf() < 0.25):
		if start_haul(p):
			return
	if builders_needed() and start_build(p):
		return
	if stock["food"] < people.size() * 12 + 200 and count_kind("farm") > 0 and start_farm(p):
		return
	if rng.randf() < 0.5 and start_work(p):
		return
	if start_gather(p, pick_gather_kind()):
		return
	if p.carry_amt > 0 and start_haul(p):
		return
	var h = nearest_building(["hall"], p.cell)
	if h != null:
		begin(p, {"type": "wander"}, Vector2i(h.center() + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))))
	p.wait = rng.randf_range(1.5, 4.0)

func arrive(p) -> void:
	var t: String = p.job.get("type", "")
	if t == "sleep":
		p.state = "sleep"
		return
	if t == "wander" or t == "":
		end_job(p)
		return
	p.state = "work"
	p.work_t = float(p.job.get("dur", 1.0))

func work_tick(p, dt: float) -> void:
	var t: String = p.job.get("type", "")
	match t:
		"build":
			var b = building_by_id(int(p.job["bid"]))
			if b == null or b.done:
				end_job(p)
				return
			b.progress += dt * (1.0 + 0.1 * era)
			if b.progress >= b.need:
				complete_building(b)
				end_job(p)
		"farm":
			stock["food"] += dt * 0.42 * FARM_MULT[era]
			p.work_t -= dt
			if p.work_t <= 0.0:
				end_job(p)
		"work":
			var wb = building_by_id(int(p.job["bid"]))
			if wb == null:
				end_job(p)
				return
			match wb.kind:
				"factory": stock["gold"] += dt * 0.55 * (1.0 + 0.1 * era)
				"school": tech += dt * 0.06
				"market":
					stock["gold"] += dt * 0.30
					stock["food"] += dt * 0.10
			p.work_t -= dt
			if p.work_t <= 0.0:
				end_job(p)
		"gather":
			p.work_t -= dt
			if p.work_t > 0.0:
				return
			var tc: Vector2i = p.job["target"]
			var kind: String = p.job["kind"]
			var got: int = res.harvest(tc.x, tc.y, 10)
			var eat: bool = p.job.get("eat", false)
			end_job(p)
			if got <= 0:
				return
			if eat:
				p.hunger = minf(100.0, p.hunger + got * 1.8)
				return
			p.carry_kind = kind
			p.carry_amt += got
			if p.carry_amt >= 20:
				start_haul(p)
			elif not start_gather(p, kind):
				start_haul(p)
		"haul":
			p.work_t -= dt
			if p.work_t <= 0.0:
				if p.carry_amt > 0 and p.carry_kind != "":
					stock[p.carry_kind] += p.carry_amt
				p.carry_amt = 0
				p.carry_kind = ""
				end_job(p)
		"eat":
			p.work_t -= dt
			if p.work_t <= 0.0:
				if stock["food"] >= 3:
					stock["food"] -= 3
					p.hunger = minf(100.0, p.hunger + 70.0)
				end_job(p)
		_:
			end_job(p)

func step_move(p, dt: float) -> bool:
	if p.path.is_empty():
		return true
	var target := Vector2(p.path[0]) + Vector2(0.5, 0.5)
	var d: Vector2 = target - p.cell
	var x := int(p.cell.x)
	var y := int(p.cell.y)
	var m := 1.0
	match data.biome_at(x, y):
		1: m = 0.5
		4: m = 0.85
		6: m = 0.75
	if data.road_at(x, y) != 0 and data.road_at(x, y) != 2:
		m = 1.4
	var step := 2.4 * m * dt * (0.45 if not is_adult(p) else 1.0)
	p.moving = true
	if d.length() > 0.001:
		p.dirv = d.normalized()
	p.anim += step * 0.85
	if absf(d.x - d.y) > 0.05:
		p.face = 1.0 if d.x - d.y > 0 else -1.0
	if d.length() <= step:
		p.cell = target
		p.path.pop_front()
	else:
		p.cell += d.normalized() * step
	return p.path.is_empty()

func kill(p, why: String) -> void:
	end_job(p)
	var h = building_by_id(p.home)
	if h != null:
		h.residents.erase(p.id)
	people.erase(p)
	deaths += 1
	if deaths <= 4:
		log_event.emit("✝ %s dog (%s, %d år)" % [p.pname, why, int(age_years(p))], false)

func tick_person(p, dt: float) -> void:
	p.moving = false
	p.hunger = maxf(0.0, p.hunger - dt * 0.45)
	if p.state == "sleep":
		var cosy := bool(p.job.get("house", false))
		p.energy = minf(100.0, p.energy + dt * (3.2 if cosy else 1.6))
	else:
		p.energy = maxf(0.0, p.energy - dt * 0.28)
	if p.hunger <= 0.0:
		p.hp -= dt * 1.2
	elif p.hp < 100.0 and p.hunger > 40.0:
		p.hp = minf(100.0, p.hp + dt * 0.6)
	if p.hp <= 0.0:
		kill(p, "svält")
		return
	if time - p.born > p.lifespan:
		kill(p, "ålder")
		return
	var jt: String = p.job.get("type", "")
	if jt != "eat" and jt != "sleep" and is_adult(p):
		if p.hunger < 22.0 and not (jt == "gather" and p.job.get("eat", false)):
			end_job(p)
			if not start_eat(p):
				p.wait = 1.0
		elif p.energy < 10.0:
			end_job(p)
			start_sleep(p)
	match p.state:
		"idle":
			p.wait -= dt
			if p.wait <= 0.0:
				think(p)
		"move":
			if step_move(p, dt):
				arrive(p)
		"work":
			work_tick(p, dt)
		"sleep":
			if p.energy >= 95.0:
				p.state = "idle"
				end_job(p)

# ---------- städer ----------
func update_towns() -> void:
	var halls: Array = []
	for t in towns:
		t["pop"] = 0
		halls.append(building_by_id(t["hall"]))
	for p in people:
		var best := -1
		var bd := 1e18
		for i in halls.size():
			if halls[i] != null and halls[i].done:
				var d: float = p.cell.distance_squared_to(halls[i].center())
				if d < bd:
					bd = d
					best = i
		p.town = maxi(best, 0)
		if best >= 0:
			towns[best]["pop"] += 1
	for t in towns:
		var lv := 0
		for i in LEVEL_T.size():
			if t["pop"] >= LEVEL_T[i]:
				lv = i
		if lv > t["level"]:
			t["level"] = lv
			log_event.emit("📈 %s växer till %s (%d invånare)" % [t["name"], LEVEL_NAMES[lv].to_lower(), t["pop"]], true)

func next_era_text() -> String:
	if era >= ERA_NAMES.size() - 1:
		return "Högsta tidsåldern i den här versionen"
	var n := era + 1
	return "Mot %s (tidigast %d): teknik %d/%d · invånare %d/%d · guld %d/%d" % [ERA_NAMES[n], ERA_YEAR[n], int(tech), ERA_TECH[n], people.size(), ERA_POP[n], stock["gold"], ERA_GOLD[n]]

func economy() -> void:
	update_towns()
	var adults := adults_count()
	stock["gold"] += adults * 0.012
	tech += adults * 0.0012 + count_kind("school") * 0.02
	var cap := housing_cap()
	if people.size() < mini(cap, MAX_PEOPLE) and stock["food"] > people.size() * 4 + 40:
		var rate := 0.025 + adults * 0.00013
		if rng.randf() < rate:
			var hs: Array = buildings.filter(func(b): return b.done and (b.kind == "house" or b.kind == "hall" or b.kind == "block"))
			if not hs.is_empty():
				var h = pick(hs)
				var kid = spawn_person(h.center() + Vector2(rng.randf_range(-1, 1), 2.0), 0.0)
				kid.hunger = 90.0
				births += 1
	for k in ["wood", "stone", "food", "gold"]:
		stock[k] = minf(stock[k], 9000.0)

func _town_cap(i: int) -> int:
	var n := 0
	for b in buildings:
		if b.done and b.town == i:
			n += cap_of(b)
	return n

func _town_count(i: int, kind: String) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind and b.town == i:
			n += 1
	return n

func _town_pending(i: int) -> int:
	var n := 0
	for b in buildings:
		if not b.done and b.town == i:
			n += 1
	return n

func _housing_kind(pop_t: int) -> String:
	if era >= 4 and pop_t >= 50 and rng.randf() < (0.5 if era == 4 else 0.75):
		return "block"
	return "house"

func _choose_kind(i: int) -> String:
	var t: Dictionary = towns[i]
	var pop_t: int = t["pop"]
	var cap_t := _town_cap(i)
	var adults_t := int(pop_t * 0.75)
	var farms_t := _town_count(i, "farm")
	if pop_t >= cap_t - 2:
		return _housing_kind(pop_t)
	if farms_t * 5.0 * FARM_MULT[era] < adults_t * 0.55 and farms_t < adults_t / 3 + 2:
		return "farm"
	if era >= 1 and pop_t >= 25 and _town_count(i, "school") < 1 + pop_t / 150:
		return "school"
	if era >= 2 and pop_t >= 35 and _town_count(i, "market") < 1 + pop_t / 120:
		return "market"
	if era >= 2 and pop_t >= 45 and _town_count(i, "church") < 1 + pop_t / 160:
		return "church"
	if era >= 4 and pop_t >= 90 and _town_count(i, "factory") < pop_t / 70:
		return "factory"
	if pop_t >= cap_t - 7:
		return _housing_kind(pop_t)
	return ""

func ai_build() -> void:
	if people.size() < 3:
		return
	var order: Array = range(towns.size())
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var tmp = order[k]
		order[k] = order[j]
		order[j] = tmp
	var started := 0
	for i in order:
		if started >= 3:
			break
		if _town_pending(i) >= 1:
			continue
		var hall = building_by_id(towns[i]["hall"])
		if hall == null or not hall.done:
			continue
		var kind := _choose_kind(i)
		if kind == "":
			continue
		var cost := cost_of(kind)
		if not can_afford(cost):
			continue
		var site := plan_site(hall, int(SPEC[kind]["size"]), kind == "farm")
		if site.x < 0:
			continue
		pay(cost)
		var nb = add_building(kind, site, false)
		nb.town = i
		started += 1
	# läger nära träd/sten (globalt)
	var camp := ""
	if stock["wood"] >= 60 and _camp_needed("wood"):
		camp = "wood"
	elif stock["wood"] >= 60 and stock["stone"] < 80 + 60 * era and _camp_needed("stone"):
		camp = "stone"
	if camp != "":
		var halls: Array = buildings.filter(func(b): return b.kind == "hall" and b.done)
		if not halls.is_empty():
			var h = pick(halls)
			var code := ResModel.TREE if camp == "wood" else ResModel.ROCK
			var t: Vector2i = res.find_nearest(code, Vector2i(h.center()), 45)
			if t.x >= 0:
				var site := find_site(Vector2(t) + Vector2(0.5, 0.5), 2, 2, 6)
				if site.x >= 0:
					stock["wood"] -= 60
					var nb2 = add_building("camp", site, false)
					nb2.variant = camp

func _camp_needed(kind: String) -> bool:
	var code := ResModel.TREE if kind == "wood" else ResModel.ROCK
	var halls: Array = buildings.filter(func(b): return b.kind in ["hall", "camp"] and b.done)
	if halls.is_empty():
		return false
	for d in halls:
		var t: Vector2i = res.find_nearest(code, Vector2i(d.center()), 14)
		if t.x >= 0:
			return false
	var far: Vector2i = res.find_nearest(code, Vector2i(halls[0].center()), 45)
	return far.x >= 0

func check_era() -> void:
	if era >= ERA_NAMES.size() - 1:
		return
	var n := era + 1
	if year() >= ERA_YEAR[n] and tech >= ERA_TECH[n] and people.size() >= ERA_POP[n] and stock["gold"] >= ERA_GOLD[n]:
		stock["gold"] -= ERA_GOLD[n]
		era = n
		log_event.emit("🏰 %s inleds! (%d invånare, teknik %d)" % [ERA_NAMES[era], people.size(), int(tech)], true)
		if era == 3 or era == 5:
			upgrade_roads()

func colonize() -> void:
	if towns.size() >= mini(30, 3 + people.size() / 40) or stock["wood"] < 120 or stock["food"] < 150:
		return
	for b in buildings:
		if b.kind == "hall" and not b.done:
			return
	var src_i := 0
	var best_pop := -1
	for i in towns.size():
		if towns[i]["pop"] > best_pop:
			best_pop = towns[i]["pop"]
			src_i = i
	if best_pop < 22:
		return
	var src = building_by_id(towns[src_i]["hall"])
	if src == null:
		return
	var halls: Array = buildings.filter(func(b): return b.kind == "hall")
	var site := Vector2i(-1, -1)
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(20, 36)
		var c := Vector2i(int(src.center().x + cos(a) * r) - 1, int(src.center().y + sin(a) * r) - 1)
		var ok := can_place(c, 3, 2)
		if ok:
			for h in halls:
				if h.center().distance_to(Vector2(c) + Vector2(1.5, 1.5)) < 16.0:
					ok = false
		if ok and pathing.nearest_walkable(c) == c:
			site = c
			break
	if site.x < 0:
		return
	stock["wood"] -= 80
	var hall = add_building("hall", site, false)
	var sent := 0
	for p in people:
		if sent >= 5:
			break
		if is_adult(p) and p.job.get("type", "") != "build" and p.state != "sleep" and p.town == src_i:
			end_job(p)
			hall.builders += 1
			if begin(p, {"type": "build", "bid": hall.id}, Vector2i(hall.center())):
				sent += 1
			else:
				hall.builders -= 1
	log_event.emit("🧭 Nybyggare lämnar %s för att grunda en ny stad…" % towns[src_i]["name"], false)

func step(dt: float) -> void:
	time += dt
	res.time_ref = time
	var i := people.size() - 1
	while i >= 0:
		if i < people.size():
			tick_person(people[i], dt)
		i -= 1
	acc_eco += dt
	if acc_eco >= 1.0:
		acc_eco -= 1.0
		economy()
	acc_ai += dt
	if acc_ai >= 4.0:
		acc_ai = 0.0
		ai_build()
	acc_era += dt
	if acc_era >= 5.0:
		acc_era = 0.0
		check_era()
	acc_col += dt
	if acc_col >= 40.0:
		acc_col = 0.0
		if time > 1500.0:
			colonize()

func summary() -> String:
	var adults := adults_count()
	return "%s | inv %d (vuxna %d) f%d d%d | hus %d block %d åker %d fabrik %d skola %d | städer %d | trä %d mat %d sten %d guld %d tek %d | %s" % [
		date_text(), people.size(), adults, births, deaths, count_kind("house"), count_kind("block"), count_kind("farm"), count_kind("factory"), count_kind("school"),
		towns.size(), stock["wood"], stock["food"], stock["stone"], stock["gold"], int(tech), ERA_NAMES[era]]
