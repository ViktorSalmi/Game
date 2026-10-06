extends SceneTree
func _init() -> void:
	var WG = load("res://scripts/world_gen.gd")
	for sd in [1621, 7, 42]:
		var d = WG.generate(sd, 384)
		print("seed %d: sjö %d å %d skog %d gräs %d berg %d start %s" % [sd, d.counts[0], d.counts[1], d.counts[4], d.counts[3], d.counts[6], d.start_cell])
	quit()
