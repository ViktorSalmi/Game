extends RefCounted
## Isometrisk 2:1-projektion. En ruta (cell) är en diamant 64x32 px.

const TW := 64.0
const TH := 32.0

static func to_screen(x: float, y: float) -> Vector2:
	return Vector2((x - y) * TW * 0.5, (x + y) * TH * 0.5)

static func to_cell(p: Vector2) -> Vector2:
	var a := p.x / (TW * 0.5)
	var b := p.y / (TH * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)
