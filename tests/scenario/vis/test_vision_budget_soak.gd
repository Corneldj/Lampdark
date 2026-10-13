extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-03's budget (Proposed 0.8 ms at p99 for five miners). The engine-finale map and the Deck
## belong to QA-03; this measures five lamp-carrying miners turning and walking on the two-cell
## test map for 60 s of ticks and prints the stage's p50 and p99.

const W = preload("res://tests/scenario/vis/vis_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_five_miners() -> void:
	var s: Scenario = make({"seed": 77, "fixture": "test"})
	var tiles: Array[Vector2i] = [Vector2i(2, 1), Vector2i(5, 13), Vector2i(12, 14), Vector2i(10, 8), Vector2i(25, 1)]
	var lamps: Array[int] = []
	for i: int in 5:
		var h: MinerHandle = s.add_miner("m%d" % i, tiles[i])
		lamps.append(W.lamp(s, Vector2(tiles[i]) + Vector2(0.5, 0.5), 5.5, h.entity_id))
		for leg: int in 60:
			h.at(leg * 20).face(float((leg * 47 + i * 72) % 360))
	var walkers: Array[MinerHandle] = s.miners
	s.on_tick = func(sc: Scenario) -> void:
		for i: int in walkers.size():
			var e: SimEntity = sc.run.registry.get_entity(walkers[i].entity_id)
			var x: float = float(tiles[i].x) + 0.5 + 0.5 * sin(sc.run.tick * 0.05 + i)
			sc.run.registry.move(e.id, Vector2(x, e.position.y))
			sc.run.light.grid.update_point(lamps[i], e.position, 5.5, 1.0)
	s.step(1200)
	var key: String = TickTimer.stage_key(StageTable.Stage.VISIBILITY)
	var p50: int = s.run.timer.percentile(key, 50.0)
	var p99: int = s.run.timer.percentile(key, 99.0)
	gut.p("visibility, five miners: p50 %d us, p99 %d us (budget %.0f us)" % [p50, p99, Tuning.f(&"vision.budget_ms_p99") * 1000.0])
	assert_lt(p99, roundi(Tuning.f(&"vision.budget_ms_p99") * 1000.0), "within VIS-03's 0.8 ms at p99")
