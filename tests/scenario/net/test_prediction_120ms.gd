extends "res://tests/scenario/kit/scenario_test.gd"
## NET-05: at 120 ms RTT with 2% loss, a 10-minute bot walk on open floor keeps the own-position
## error at 0.05 tile or less in 99% of acknowledged ticks.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_ten_minutes_at_120_ms() -> void:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(40))
	for y: int in 26:
		rows.append("#" + ".".repeat(38) + "#")
	rows.append("#".repeat(40))
	rows[13] = "#" + ".".repeat(18) + "a" + ".".repeat(19) + "#"
	var s: Scenario = make({"seed": 80, "fixture": FixtureMap.from_ascii(rows)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var lit: Array = []
	for y: int in 28:
		for x: int in 40:
			lit.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", 3, 0, 0.6, lit)
	ann.link(120, 2.0)
	s.enable_prediction(ann)
	ann.brain = load("res://tools/bots/brain.gd").call(&"create", "wander", 5)
	s.step(12000)
	var errors: Array[float] = ann.prediction_errors
	var within: int = errors.filter(func(e: float) -> bool: return e <= 0.05).size()
	var share: float = float(within) / maxi(errors.size(), 1)
	errors.sort()
	gut.p("own-position error over %d acknowledged ticks: %.2f%% within 0.05 tile; p99 %.4f; worst %.3f; corrections %d, snaps %d" % [
		errors.size(), share * 100.0, errors[int(errors.size() * 0.99)], errors[errors.size() - 1], ann.reconciler.corrections, ann.reconciler.snaps])
	assert_gt(errors.size(), 11000)
	assert_gte(share, 0.99)
