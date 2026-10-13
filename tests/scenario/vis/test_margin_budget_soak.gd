extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-04's budget (Proposed 0.2 ms at p99 for five miners, within VIS-03's share): five
## lamp-carrying miners turning and walking on the two-cell test map for 60 s of ticks. The
## margin's own time is read from LbVision.margin_nanos per tick. The Deck belongs to QA-03.

const W = preload("res://tests/scenario/vis/vis_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_five_miners() -> void:
	var s: Scenario = make({"seed": 78, "fixture": "test"})
	var tiles: Array[Vector2i] = [Vector2i(2, 1), Vector2i(5, 13), Vector2i(12, 14), Vector2i(10, 8), Vector2i(25, 1)]
	var lamps: Array[int] = []
	for i: int in 5:
		var h: MinerHandle = s.add_miner("m%d" % i, tiles[i])
		lamps.append(W.lamp(s, Vector2(tiles[i]) + Vector2(0.5, 0.5), 4.0, h.entity_id))
		for leg: int in 60:
			h.at(leg * 20).face(float((leg * 47 + i * 72) % 360))
	var walkers: Array[MinerHandle] = s.miners
	var per_tick: Array[int] = []
	var margins: Array[int] = [0]
	var last: Array[int] = [0]
	s.on_tick = func(sc: Scenario) -> void:
		var now: int = sc.run.vision.native.margin_nanos()
		per_tick.append(now - last[0])
		last[0] = now
		for w: MinerHandle in walkers:
			margins[0] += _margin_tiles(sc.run.vision.frame_for(w.slot))
		for i: int in walkers.size():
			var e: SimEntity = sc.run.registry.get_entity(walkers[i].entity_id)
			var x: float = float(tiles[i].x) + 0.5 + 0.5 * sin(sc.run.tick * 0.05 + i)
			sc.run.registry.move(e.id, Vector2(x, e.position.y))
			sc.run.light.grid.update_point(lamps[i], e.position, 4.0, 1.0)
	s.step(1200)
	per_tick.sort()
	var p50: float = per_tick[per_tick.size() / 2] / 1000.0
	var p99: float = per_tick[int(per_tick.size() * 0.99)] / 1000.0
	var budget: float = Tuning.f(&"vision.margin_budget_ms_p99") * 1000.0
	gut.p("margin, five miners: p50 %.1f us, p99 %.1f us (budget %.0f us); %d margin tiles over the run" % [p50, p99, budget, margins[0]])
	assert_gt(margins[0], 1000, "margins were built")
	assert_lt(p99, budget, "within 0.2 ms at p99")


static func _margin_tiles(frame: Dictionary) -> int:
	var xs: PackedInt32Array = Variants.dict(frame.get("margin_tiles", {})).get("x", PackedInt32Array())
	return xs.size()
