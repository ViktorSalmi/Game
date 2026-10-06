extends RefCounted
## Läser kartdata (boras-data.json från tools/bake-boras.mjs). Motoroberoende format.
## Biomer: 0 sjö, 1 å/vad, 2 sand, 3 gräs/åker, 4 skog, 5 torrt, 6 berg, 7 snö, 8 myr, 9 bebyggelse, 10 utanför kommunen

const BIOME_NAMES := ["Sjö", "Å / vad", "Sand", "Gräs / åker", "Skog", "Torr mark", "Berg", "Snö", "Myr", "Bebyggelse", "Utanför kommunen"]

var ok := false
var source := ""
var map_name := "Okänd karta"
var w := 0
var h := 0
var cell_m := 50.0
var bbox: Array = []
var biome := PackedByteArray()
var road := PackedByteArray()
var elev := PackedFloat32Array()
var ew := 0
var eh := 0
var estep := 20
var lo := 0.0
var hi := 1.0
var places: Array = []
var pois: Array = []
var counts := PackedInt32Array()
var bld := PackedInt32Array()       # x4,y4,w4,h4,meta (kvartsrutor; meta = typ*16+våningar)
var bld_index := {}                 # Vector2i(kartbit) -> PackedInt32Array med startindex i bld
const CS := 32

func load_any(extra_path: String = "") -> bool:
	var candidates: Array = []
	if extra_path != "":
		candidates.append(extra_path)
	candidates.append("res://data/boras-data.json")
	candidates.append(ProjectSettings.globalize_path("res://").path_join("../data/boras-data.json").simplify_path())
	for p in candidates:
		if FileAccess.file_exists(p) and load_file(p):
			source = p
			return true
	make_demo()
	return false

func load_file(path: String) -> bool:
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY or int(d.get("v", 0)) != 1:
		return false
	w = int(d["w"])
	h = int(d["h"])
	cell_m = float(d["cell"])
	bbox = d["bbox"]
	map_name = String(d.get("name", "Karta"))
	biome = _rle(d["biome"], w * h)
	road = _rle(d["road"], w * h)
	ew = int(d["ew"])
	eh = int(d["eh"])
	estep = int(d["estep"])
	lo = float(d["lo"])
	hi = float(d["hi"])
	elev = PackedFloat32Array()
	elev.resize(ew * eh)
	var ea: Array = d["elev"]
	for i in range(min(ea.size(), elev.size())):
		elev[i] = float(ea[i])
	places = d["places"]
	pois = d["pois"]
	bld = PackedInt32Array(d.get("bld", []))
	_index_buildings()
	_stats()
	ok = true
	return true

func _index_buildings() -> void:
	bld_index.clear()
	for i in range(0, bld.size() - 4, 5):
		var cx := int((bld[i] + bld[i + 2] * 0.5) / 4.0) / CS
		var cy := int((bld[i + 1] + bld[i + 3] * 0.5) / 4.0) / CS
		var k := Vector2i(cx, cy)
		if not bld_index.has(k):
			bld_index[k] = PackedInt32Array()
		bld_index[k].append(i)

func buildings_in_chunk(c: Vector2i) -> PackedInt32Array:
	return bld_index.get(c, PackedInt32Array())

func _rle(arr: Array, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	for i in range(0, arr.size(), 2):
		var seg := PackedByteArray()
		seg.resize(int(arr[i + 1]))
		seg.fill(int(arr[i]))
		out.append_array(seg)
	if out.size() < n:
		var pad := PackedByteArray()
		pad.resize(n - out.size())
		pad.fill(10)
		out.append_array(pad)
	return out

func _stats() -> void:
	counts = PackedInt32Array()
	counts.resize(11)
	for i in range(biome.size()):
		counts[biome[i]] += 1

## Liten påhittad karta om ingen datafil hittas, så att projektet ändå går att köra.
func make_demo() -> void:
	w = 300
	h = 300
	cell_m = 50.0
	map_name = "DEMO (ingen kartdata hittades)"
	bbox = [57.56, 12.64, 57.92, 13.32]
	var n := FastNoiseLite.new()
	n.frequency = 0.012
	biome = PackedByteArray()
	biome.resize(w * h)
	road = PackedByteArray()
	road.resize(w * h)
	for y in range(h):
		for x in range(w):
			var e := n.get_noise_2d(x, y)
			var b := 3
			if e < -0.25:
				b = 0
			elif e > 0.35:
				b = 6
			elif e > 0.05:
				b = 4
			biome[y * w + x] = b
	ew = int(ceil(w / 20.0)) + 1
	eh = int(ceil(h / 20.0)) + 1
	estep = 20
	elev = PackedFloat32Array()
	elev.resize(ew * eh)
	for i in range(elev.size()):
		elev[i] = 200.0
	lo = 150.0
	hi = 250.0
	places = [{"n": "Demostad", "t": "city", "x": 150, "y": 150}]
	pois = []
	_stats()
	ok = true

func biome_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 10
	return biome[y * w + x]

func road_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 0
	return road[y * w + x]

func elev_at(x: float, y: float) -> float:
	if elev.is_empty():
		return 0.0
	var fx := clampf(x / estep, 0.0, ew - 1.001)
	var fy := clampf(y / estep, 0.0, eh - 1.001)
	var x0 := int(fx)
	var y0 := int(fy)
	var u := fx - x0
	var v := fy - y0
	var i := y0 * ew + x0
	return lerpf(lerpf(elev[i], elev[i + 1], u), lerpf(elev[i + ew], elev[i + ew + 1], u), v)

func is_walkable(x: int, y: int) -> bool:
	var b := biome_at(x, y)
	return b != 0 and b != 7 and b != 10

func latlon(x: float, y: float) -> Vector2:
	if bbox.size() < 4:
		return Vector2.ZERO
	var lat := float(bbox[2]) - y * cell_m / 110574.0
	var lon := float(bbox[1]) + x * cell_m / (111320.0 * cos(deg_to_rad((float(bbox[0]) + float(bbox[2])) * 0.5)))
	return Vector2(lat, lon)

func nearest_place(x: float, y: float, max_d: float = 8.0) -> String:
	var best := ""
	var bd := max_d
	for p in places:
		var d := Vector2(float(p["x"]) - x, float(p["y"]) - y).length()
		if d < bd:
			bd = d
			best = String(p["n"])
	return best

func find_place(pname: String) -> Variant:
	for p in places:
		if String(p["n"]) == pname:
			return p
	return null
