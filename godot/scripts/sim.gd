extends RefCounted
## Simuleringen (ingen grafik): människor med behov, arbete, automatisk stadsbyggnad, åldrar, kolonisering.

signal log_event(text: String, important: bool)

const Person = preload("res://scripts/person.gd")
const Building = preload("res://scripts/building.gd")
const ResModel = preload("res://scripts/res_model.gd")

const YEAR := 120.0              # spelsekunder per år
const START_YEAR := 1621
const ADULT := 14.0              # år
const SPEC := {
	"hall": {"size": 3, "need": 70.0, "wood": 0, "label": "Stadshus"},
	"house": {"size": 2, "need": 22.0, "wood": 30, "label": "Hus"},
	"farm": {"size": 3, "need": 26.0, "wood": 60, "label": "Åker"},
	"camp": {"size": 2, "need": 20.0, "wood": 60, "label": "Läger"},
}
const ERA_NAMES := ["Mörka åldern", "Feudala åldern", "Slottsåldern", "Imperieåldern"]
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
var era := 0
var people: Array = []
var buildings: Array = []
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
var chunk_cb: Callable

func setup(map_data, path_grid, start: Vector2i, town_name: String, seed_value: int = 1621) -> void:
	data = map_data
	pathing = path_grid
	rng.seed = seed_value
	res = ResModel.new()
	res.setup(data)
	occupied.resize(data.w * data.h)
	var hall = add_building("hall", start - Vector2i(1, 1), true)
	used_places[town_name] = true
	towns.append({"name": town_name, "hall": hall.id})
	hall.town = 0
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
	for b in buildings:
		if b.id == id:
			return b
	return null

func count_kind(kind: String, only_done: bool = true) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind and (b.done or not only_done):
			n += 1
	return n

func housing_cap() -> int:
	return count_kind("hall") * 6 + count_kind("house") * (4 + era)

func pop() -> int:
	return people.size()

func spawn_person(c: Vector2, age: float) -> Object:
	var p := Person.new()
	p.id = next_id
	next_id += 1
	p.female = rng.randf() < 0.5
	p.pname = String(pick(FEMALE) if p.female else pick(MALE))
	p.born = time - age * YEAR
	p.lifespan = rng.randf_range(52.0, 78.0) * YEAR
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
	return b

func find_site(anchor: Vector2, size: int, rmin: int, rmax: int) -> Vector2i:
	for r in range(rmin, rmax + 1):
		for attempt in 16:
			var a := rng.randf() * TAU
			var c := Vector2i(int(anchor.x + cos(a) * r) - size / 2, int(anchor.y + sin(a) * r) - size / 2)
			if can_place(c, size):
				return c
	return Vector2i(-1, -1)

func complete_building(b) -> void:
	b.done = true
	b.progress = b.need
	if b.kind == "hall" and not towns.any(func(t): return t["hall"] == b.id):
		var nm := name_for_town(b.center())
		towns.append({"name": nm, "hall": b.id})
		b.town = towns.size() - 1
		log_event.emit("🏘 %s grundad!" % nm, true)
	elif b.kind == "house":
		pass

func name_for_town(c: Vector2) -> String:
	var best := ""
	var bd := 45.0
	for p in data.places:
		var nm := String(p["n"])
		if used_places.has(nm):
			continue
		var d: float = Vector2(float(p["x"]), float(p["y"])).distance_to(c)
		if d < bd:
			bd = d
			best = nm
	if best == "":
		best = String(pick(GEN_A)) + String(pick(GEN_B))
	used_places[best] = true
	return best

# ---------- resurser / roller ----------
func kind_code(kind: String) -> int:
	return {"wood": ResModel.TREE, "food": ResModel.BUSH, "stone": ResModel.ROCK}[kind]

func pick_gather_kind() -> String:
	var farms := count_kind("farm")
	var w := {
		"wood": maxf(0.15, (260.0 - stock["wood"]) / 260.0 + 0.35),
		"stone": maxf(0.0, (140.0 - stock["stone"]) / 140.0) * 0.7,
		"food": maxf(0.0, (220.0 - stock["food"]) / 220.0) * (1.0 if farms == 0 else 0.4),
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
	if t == "farm":
		var b = building_by_id(int(p.job["bid"]))
		if b != null:
			b.workers = maxi(0, b.workers - 1)
	elif t == "build":
		var b = building_by_id(int(p.job["bid"]))
		if b != null:
			b.builders = maxi(0, b.builders - 1)
	p.job = {}
	p.path = []
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
		if h.kind == "house" and h.done and h.residents.size() < 4 + era:
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
	return begin(p, {"type": "sleep", "target": Vector2i(h.center()), "house": h.kind == "house"}, Vector2i(h.center()))

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
	if stock["food"] < 400 and count_kind("farm") > 0 and start_farm(p):
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
			stock["food"] += dt * 0.42 * (1.0 + 0.25 * era)
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
	if deaths <= 6 or deaths % 10 == 0:
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

# ---------- ekonomi & AI ----------
func economy() -> void:
	var adults := 0
	for p in people:
		if is_adult(p):
			adults += 1
	stock["gold"] += adults * 0.012
	var cap := housing_cap()
	if people.size() < cap and stock["food"] > people.size() * 8 and rng.randf() < 0.05:
		var h = nearest_building(["house", "hall"], Vector2(data.w, data.h) * 0.5)
		var hs: Array = buildings.filter(func(b): return b.done and (b.kind == "house" or b.kind == "hall"))
		if not hs.is_empty():
			h = pick(hs)
			var c: Vector2 = h.center() + Vector2(rng.randf_range(-1, 1), 2.0)
			var kid = spawn_person(c, 0.0)
			kid.hunger = 90.0
			births += 1
	for k in ["wood", "stone", "food", "gold"]:
		stock[k] = minf(stock[k], 5000.0)

func ai_build() -> void:
	var pending := 0
	for b in buildings:
		if not b.done:
			pending += 1
	if pending >= 2 or people.size() < 3:
		return
	var n := people.size()
	var cap := housing_cap()
	var farms := count_kind("farm")
	var kind := ""
	if n >= cap - 2 and stock["wood"] >= 30:
		kind = "house"
	elif farms * 5 < n * 0.45 and stock["wood"] >= 60:
		kind = "farm"
	elif stock["wood"] >= 60 and _camp_needed("wood"):
		kind = "camp_wood"
	elif stock["wood"] >= 60 and stock["stone"] < 80 and _camp_needed("stone"):
		kind = "camp_stone"
	elif n >= cap - 4 and stock["wood"] >= 30:
		kind = "house"
	elif stock["wood"] > 350 and rng.randf() < 0.5:
		kind = "house" if rng.randf() < 0.6 else "farm"
	if kind == "":
		return
	var halls: Array = buildings.filter(func(b): return b.kind == "hall" and b.done)
	if halls.is_empty():
		return
	var site := Vector2i(-1, -1)
	var bk := kind
	if kind.begins_with("camp"):
		bk = "camp"
		var code := ResModel.TREE if kind == "camp_wood" else ResModel.ROCK
		var h = pick(halls)
		var t: Vector2i = res.find_nearest(code, Vector2i(h.center()), 45)
		if t.x >= 0:
			site = find_site(Vector2(t) + Vector2(0.5, 0.5), 2, 2, 6)
	else:
		var h = pick(halls)
		site = find_site(h.center(), int(SPEC[bk]["size"]), 4, 16)
	if site.x < 0:
		return
	var w := int(SPEC[bk]["wood"])
	if stock["wood"] < w:
		return
	stock["wood"] -= w
	add_building(bk, site, false)

func _camp_needed(kind: String) -> bool:
	var code := ResModel.TREE if kind == "wood" else ResModel.ROCK
	var halls: Array = buildings.filter(func(b): return b.kind in ["hall", "camp"] and b.done)
	if halls.is_empty():
		return false
	var h = halls[0]
	var best := 1e9
	for d in halls:
		var t: Vector2i = res.find_nearest(code, Vector2i(d.center()), 14)
		if t.x >= 0:
			return false
	var far: Vector2i = res.find_nearest(code, Vector2i(h.center()), 45)
	return far.x >= 0

func check_era() -> void:
	var n := people.size()
	var houses := count_kind("house")
	if era == 0 and n >= 18 and houses >= 3 and stock["food"] >= 250 and stock["gold"] >= 80:
		stock["food"] -= 250
		stock["gold"] -= 80
		era = 1
	elif era == 1 and n >= 45 and towns.size() >= 2 and stock["food"] >= 500 and stock["gold"] >= 250:
		stock["food"] -= 500
		stock["gold"] -= 250
		era = 2
	elif era == 2 and n >= 100 and stock["food"] >= 900 and stock["gold"] >= 600:
		stock["food"] -= 900
		stock["gold"] -= 600
		era = 3
	else:
		return
	log_event.emit("🏰 %s inleds! (%d invånare)" % [ERA_NAMES[era], n], true)

func colonize() -> void:
	if people.size() < 24 or stock["wood"] < 160 or stock["food"] < 160 or towns.size() >= 14:
		return
	for b in buildings:
		if b.kind == "hall" and not b.done:
			return
	var halls: Array = buildings.filter(func(b): return b.kind == "hall" and b.done)
	var src = pick(halls)
	var site := Vector2i(-1, -1)
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(20, 34)
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
	stock["wood"] -= 100
	var hall = add_building("hall", site, false)
	var sent := 0
	for p in people:
		if sent >= 5:
			break
		if is_adult(p) and p.job.get("type", "") != "build" and p.state != "sleep":
			end_job(p)
			hall.builders += 1
			if begin(p, {"type": "build", "bid": hall.id}, Vector2i(hall.center())):
				sent += 1
			else:
				hall.builders -= 1
	log_event.emit("🧭 Nybyggare lämnar för att grunda en ny stad…", false)

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
	if acc_ai >= 6.0:
		acc_ai = 0.0
		ai_build()
	acc_era += dt
	if acc_era >= 5.0:
		acc_era = 0.0
		check_era()
	acc_col += dt
	if acc_col >= 30.0:
		acc_col = 0.0
		colonize()

func summary() -> String:
	var adults := 0
	for p in people:
		if is_adult(p):
			adults += 1
	return "%s | invånare %d (vuxna %d) födda %d döda %d | hus %d åker %d läger %d städer %d | trä %d mat %d sten %d guld %d | %s" % [
		date_text(), people.size(), adults, births, deaths, count_kind("house"), count_kind("farm"), count_kind("camp"), towns.size(),
		stock["wood"], stock["food"], stock["stone"], stock["gold"], ERA_NAMES[era]]
