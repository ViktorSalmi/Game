extends SceneTree
## Kör simuleringen utan grafik och skriver ut utvecklingen.  godot --headless --path godot -s tests/sim_test.gd -- --seconds=3000

func _init() -> void:
	var MapData = load("res://scripts/map_data.gd")
	var Pathing = load("res://scripts/pathing.gd")
	var Sim = load("res://scripts/sim.gd")
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var d = MapData.new()
	d.load_any(String(args.get("data", "")))
	var pg = Pathing.new()
	pg.setup(d)
	var bp = d.find_place("Borås")
	var start := Vector2i(d.w / 2, d.h / 2) if bp == null else Vector2i(int(bp["x"]), int(bp["y"]))
	start = pg.nearest_walkable(start)
	var sim = Sim.new()
	sim.log_event.connect(func(t, imp): if imp: print("   ", t))
	sim.setup(d, pg, start, "Borås")
	var total := float(args.get("seconds", "3000"))
	var t0 := Time.get_ticks_msec()
	var next_report := 300.0
	while sim.time < total:
		sim.step(0.1)
		if sim.time >= next_report:
			print(sim.summary())
			next_report += 300.0
	print("KLART på %d ms (%d sim-sekunder)" % [Time.get_ticks_msec() - t0, int(total)])
	quit()
