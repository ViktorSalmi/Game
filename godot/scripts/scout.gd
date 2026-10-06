extends Node2D
## Platshållare: en platt, generisk figur. Ger synfält i fog of war. Högerklick = flytta.

const Iso = preload("res://scripts/iso.gd")

var data
var cell := Vector2(0, 0)
var path: Array[Vector2i] = []
var base_speed := 8.0
var vision := 14.0

func setup(map_data, start: Vector2) -> void:
	data = map_data
	cell = start
	position = Iso.to_screen(cell.x, cell.y)

func command_path(p: Array[Vector2i]) -> void:
	path = p

func speed_here() -> float:
	var x := int(cell.x)
	var y := int(cell.y)
	var m := 1.0
	match data.biome_at(x, y):
		1: m = 0.5
		4: m = 0.8
		6: m = 0.7
	if data.road_at(x, y) == 1:
		m = 1.5
	return base_speed * m

func _process(dt: float) -> void:
	if path.is_empty():
		return
	var target := Vector2(path[0]) + Vector2(0.5, 0.5)
	var d := target - cell
	var step := speed_here() * dt
	if d.length() <= step:
		cell = target
		path.pop_front()
	else:
		cell += d.normalized() * step
	position = Iso.to_screen(cell.x, cell.y)
	queue_redraw()

func _draw() -> void:
	# platt platshållare: skugga, kropp, huvud
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-4, -16, 8, 12), Color("e5484d"))
	draw_circle(Vector2(0, -20), 4.5, Color("f1c9a0"))
	draw_arc(Vector2(0, -20), 4.5, 0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
