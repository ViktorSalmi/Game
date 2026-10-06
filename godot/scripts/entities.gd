extends Node2D
## Ritar spelets levande delar: stadens byggnader och människor, som sprites.

const Iso = preload("res://scripts/iso.gd")
const PERSON_SCALE := 0.32
const FIT := {"tent_a": 0.7, "tent_b": 0.7, "hut_a": 0.8, "hut_b": 0.8, "longhouse_a": 0.95, "cave": 1.0, "campfire": 0.55}

var sim
var sprites
var data
var scout
var view_min := Vector2.ZERO
var view_max := Vector2(1e9, 1e9)
var selected = null

func _process(_dt: float) -> void:
	queue_redraw()

func sprite_for(b) -> String:
	var h: int = int(b.id) % 3
	match b.kind:
		"cave":
			return "cave"
		"hall":
			if sim.era == 0:
				return "campfire"
			return "hall_long" if sim.era < 3 else "hall_keep"
		"house":
			match sim.era:
				0: return ["tent_a", "tent_b", "hut_a"][h]
				1: return ["hut_a", "hut_b", "longhouse_a"][h]
				2: return ["timber_a", "timber_b", "timber_c"][h]
				_: return ["stone_a", "stone_b", "stone_c"][h]
		"farm":
			return "field_gold" if h == 1 else "field_green"
		"camp":
			return "camp_stone" if b.variant == "stone" else "camp_wood"
	return "house_red_M"

func person_color(p) -> String:
	var t: String = p.job.get("type", "")
	if t == "build":
		return "orange"
	if t == "farm":
		return "green"
	if t == "gather":
		match String(p.job.get("kind", "")):
			"wood": return "brown"
			"stone": return "grey"
			"food": return "green"
	if p.carry_amt > 0:
		return {"wood": "brown", "stone": "grey", "food": "green"}.get(p.carry_kind, "blue")
	return "blue"

func _person_sprite(color: String, dirv: Vector2, anim: float, moving: bool) -> String:
	var yaw := atan2(dirv.x, dirv.y)
	var k := int(round(yaw / (PI / 4.0)))
	k = ((k % 8) + 8) % 8
	if not moving:
		return "person_%s_%d_idle" % [color, k]
	return "person_%s_%d_%d" % [color, k, int(anim * 1.6) % 6]

func _in_view(c: Vector2, margin: float = 6.0) -> bool:
	return c.x > view_min.x - margin and c.x < view_max.x + margin and c.y > view_min.y - margin and c.y < view_max.y + margin

func _draw() -> void:
	if sim == null or sprites == null or not sprites.ok:
		return
	var cm: float = data.cell_m
	var list: Array = []
	for b in sim.buildings:
		var c: Vector2 = b.center()
		if not _in_view(c, 10.0):
			continue
		var nm := sprite_for(b)
		if b.kind == "farm":
			var sc: float = sprites.scale_for_len(nm, b.size * cm * 1.02, cm)
			sprites.draw(self, nm, Iso.to_screen(c.x, c.y), sc, false, Color(1, 1, 1, 1.0 if b.done else 0.5))
			if not b.done:
				_progress(b, c)
			continue
		list.append([c.x + c.y, 0, b, nm])
	for p in sim.people:
		if _in_view(p.cell):
			list.append([p.cell.x + p.cell.y + 0.05, 1, p, ""])
	if scout != null:
		list.append([scout.cell.x + scout.cell.y + 0.05, 2, scout, ""])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for it in list:
		match it[1]:
			0:
				var b = it[2]
				var nm: String = it[3]
				var c: Vector2 = b.center()
				var fit: float = FIT.get(nm, 0.95)
				var sc: float = sprites.scale_for_len(nm, b.size * cm * fit, cm)
				var pos := Iso.to_screen(c.x, c.y)
				sprites.draw(self, "shadow", pos + Vector2(sc * 40.0, sc * 14.0), sc * 1.4, false, Color(1, 1, 1, 0.8))
				var a := 1.0 if b.done else 0.45
				sprites.draw(self, nm, pos, sc, false, Color(1, 1, 1, a))
				if not b.done:
					_progress(b, c)
				if selected == b:
					_ring(pos, b.size * 30.0)
			1:
				var p = it[2]
				var pos := Iso.to_screen(p.cell.x, p.cell.y)
				var kid: float = 0.7 if not sim.is_adult(p) else 1.0
				sprites.draw(self, "shadow", pos + Vector2(2, 1), 0.07 * kid, false, Color(1, 1, 1, 0.8))
				sprites.draw(self, _person_sprite(person_color(p), p.dirv, p.anim, p.moving), pos, PERSON_SCALE * kid)
				if p.state == "sleep":
					draw_string(ThemeDB.fallback_font, pos + Vector2(6, -22), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))
				if selected == p:
					_ring(pos, 12.0)
			2:
				var s = it[2]
				var pos := Iso.to_screen(s.cell.x, s.cell.y)
				sprites.draw(self, "shadow", pos + Vector2(2, 1), 0.07, false, Color(1, 1, 1, 0.8))
				sprites.draw(self, _person_sprite("red", s.dirv, s.anim, s.moving), pos, PERSON_SCALE * 1.1)

func _progress(b, c: Vector2) -> void:
	var pos := Iso.to_screen(c.x, c.y) + Vector2(-16, 10)
	draw_rect(Rect2(pos, Vector2(32, 4)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(pos, Vector2(32.0 * clampf(b.progress / b.need, 0.0, 1.0), 4)), Color("ffd45a"))

func _ring(pos: Vector2, r: float) -> void:
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0, TAU, 28, Color(1, 0.9, 0.4, 0.95), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
