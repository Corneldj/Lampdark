extends "res://tests/scenario/kit/scenario_test.gd"
## NET-04's byte budget: no frame over an unreliable message, no 1 s window over 64 kbps (voice
## excluded), and a big first view converges within a few seconds, geometry before light.

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_five_lamp_carriers_stay_under_the_budget() -> void:
	var s: Scenario = make({"seed": 44, "fixture": "test"})
	var tiles: Array[Vector2i] = [Vector2i(2, 1), Vector2i(5, 13), Vector2i(12, 14), Vector2i(10, 8), Vector2i(25, 1)]
	var lamps: Array[int] = []
	for i: int in 5:
		var h: MinerHandle = s.add_miner("m%d" % i, tiles[i])
		lamps.append(N.lamp(s, Vector2(tiles[i]) + Vector2(0.5, 0.5), 5.5, h.entity_id))
		h.brain = load("res://tools/bots/brain.gd").call(&"create", "wander", 100 + i)
	s.on_tick = func(sc: Scenario) -> void:
		for i: int in sc.miners.size():
			var e: SimEntity = sc.run.registry.get_entity(sc.miners[i].entity_id)
			sc.run.light.grid.update_point(lamps[i], e.position, 5.5, 1.0)
	s.step(600)
	var budget_bytes: int = roundi(Tuning.f(&"net.down_budget_kbps") * 1000.0 / 8.0)
	var worst_window: int = 0
	var worst_frame: int = 0
	for h: MinerHandle in s.miners:
		var per_tick: Dictionary = {}
		for m: Dictionary in s.client(h).messages:
			if int(Variants.number(m["lane"])) == Lane.Id.VOICE:
				continue
			var bytes: PackedByteArray = m["bytes"]
			per_tick[m["tick"]] = int(Variants.number(per_tick.get(m["tick"], 0))) + bytes.size()
			if int(Variants.number(m["type"])) == Protocol.Msg.FRAME:
				worst_frame = maxi(worst_frame, bytes.size())
		for start: int in range(0, 600 - 20):
			var total: int = 0
			for t: int in range(start, start + 20):
				total += int(Variants.number(per_tick.get(t, 0)))
			worst_window = maxi(worst_window, total)
	gut.p("five wandering lamp carriers: worst 1 s window %d bytes (budget %d), worst frame %d bytes" % [worst_window, budget_bytes, worst_frame])
	assert_lte(worst_window, budget_bytes + Tuning.i(&"net.down_burst_bytes"), "within the budget and its burst")
	assert_lte(worst_frame, Tuning.i(&"net.unreliable_max_bytes"), "no frame over an unreliable message")


func test_a_big_view_converges_geometry_first() -> void:
	var s: Scenario = make({"seed": 45, "fixture": "test"})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 13), {"facing_deg": 0.0})
	var area: Array = []
	for y: int in range(0, 20):
		for x: int in range(0, 40):
			area.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", 3, 0, 0.6, area)
	s.step(1)
	var first: Dictionary = s.run.replication.native.last_stats(ann.slot)
	s.step(80)
	var settled: Dictionary = s.run.replication.native.last_stats(ann.slot)
	gut.p("first frame: %s" % first)
	assert_eq(int(Variants.number(settled["tiles_pending"])) + int(Variants.number(settled["geometry_pending"])), 0, "converged")
	var view: ReceivedView = s.client(ann).records_at(80)
	var seen: PackedInt32Array = Variants.dict(s.run.vision.frame_for(ann.slot)["tiles"])["x"]
	assert_eq(view.tiles.size(), seen.size(), "the client holds every seen tile")
