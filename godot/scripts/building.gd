extends RefCounted

var id := 0
var kind := "house"
var cell := Vector2i.ZERO   # övre vänstra rutan
var size := 2
var progress := 0.0
var need := 20.0
var done := false
var town := 0
var residents: Array = []
var workers := 0
var builders := 0
var variant := ""

func center() -> Vector2:
	return Vector2(cell) + Vector2(size, size) * 0.5

func contains(c: Vector2) -> bool:
	return c.x >= cell.x and c.y >= cell.y and c.x < cell.x + size and c.y < cell.y + size
