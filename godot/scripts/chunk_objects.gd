extends Node2D
## En kartbits objekt (träd, buskar, stenar, hus) som sprites. Ritas en gång och cachas av motorn.

var sprites
var shadows: Array = []   # [pos, scale]
var items: Array = []     # [name, pos, scale, flip]

func _draw() -> void:
	for s in shadows:
		sprites.draw(self, "shadow", s[0], s[1], false, Color(1, 1, 1, 0.85))
	for it in items:
		sprites.draw(self, it[0], it[1], it[2], it[3])
