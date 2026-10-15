extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-13: replaying a typical cell's diff takes at most mine.diff_replay_budget_ms (0.2 ms,
## Proposed), inside GEN-11's commit budget, by the median of 40 evictions and returns. Typical
## (Proposed): what crews leave in a cell they pass through: 4 items lying (a lit lamp and a lit
## candle among them), 3 taken, its door worked open and an 18-tile trail (one blood row). A heavy
## cell (12 items) is measured and reported, not held to the budget: replay grows with its items.
## A wall-clock test: the round runs it alone (SOLO). With LB_TIMING_REPORT_ONLY set (shared CI
## runners, Wine) the times are printed, not asserted.

const W = preload("res://tests/scenario/world/diff_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## The cell's door open, its trail, a lit lamp, a lit candle and `extra` more items lying.
func _cell(run_seed: int, extra: Array[ItemKinds.Kind]) -> Scenario:
	var s: Scenario = make({"seed": run_seed, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", W.DOOR - Vector2i(1, 0))
	s.step(2)
	W.work_door(s, ann)
	s.run.movement.place(s.run, ann.entity_id, Vector2(3.5, 1.5))
	s.run.lamps.create(s.run, 0.9, 2, true, LampRules.WICK_NORMAL, Vector2(41.5, 1.5))
	W.put(s, ItemKinds.Kind.CANDLE, Vector2i(43, 1), {"lit": true, "burn_ticks": 5000})
	for i: int in extra.size():
		W.put(s, extra[i], Vector2i(46 + i, 1))
	for x: int in range(41, 59):
		s.run.vision.mark_trail(Vector2i(x, 1), 4)
	s.step(5)
	return s


## Median and worst replay of W.FAR over 40 returns, in ms; fails if anything is lost.
func _measure(s: Scenario, records: int, items: int) -> Array[float]:
	var samples: Array[int] = []
	for _i: int in 40:
		W.evict(s, W.FAR)
		W.restore(s, W.FAR)
		var last: Dictionary = s.run.diff_log.replays[s.run.diff_log.replays.size() - 1]
		var replayed_cell: Vector2i = last["cell"]
		assert_eq(replayed_cell, W.FAR)
		assert_eq(int(Variants.number(last["records"])), records, "every record, every return")
		samples.append(int(Variants.number(last["usec"])))
	assert_eq(s.run.inventory.world.items.size(), items, "nothing lost in 40 returns")
	samples.sort()
	return [samples[samples.size() / 2] / 1000.0, samples[samples.size() - 1] / 1000.0]


func test_a_typical_cell_replays_within_budget() -> void:
	var s: Scenario = _cell(1351, [ItemKinds.Kind.OIL_FLASK, ItemKinds.Kind.SPANNER])
	for k: String in ["p0001", "p0002", "p0003"]:
		s.run.diff_log.taken(W.FAR, k)
	var t: Array[float] = _measure(s, 4 + 3 + 1 + 1, 4)
	gut.p("typical cell: median %.3f ms, worst %.3f ms" % [t[0], t[1]])
	if OS.get_environment("LB_TIMING_REPORT_ONLY").is_empty():
		assert_lt(t[0], Tuning.f(&"mine.diff_replay_budget_ms"), "within the replay budget")


func test_a_heavy_cell_is_measured() -> void:
	var extra: Array[ItemKinds.Kind] = [ItemKinds.Kind.OIL_FLASK, ItemKinds.Kind.FUSE, ItemKinds.Kind.SPANNER, ItemKinds.Kind.HAMMER,
		ItemKinds.Kind.FLARE, ItemKinds.Kind.ROPE_CLAMP, ItemKinds.Kind.CANDLE, ItemKinds.Kind.CROWBAR, ItemKinds.Kind.MAGNETO,
		ItemKinds.Kind.FUSE]
	var s: Scenario = _cell(1352, extra)
	var t: Array[float] = _measure(s, 12 + 1 + 1, 12)
	gut.p("heavy cell (12 items): median %.3f ms, worst %.3f ms (reported, not held to the budget)" % [t[0], t[1]])
	if OS.get_environment("LB_TIMING_REPORT_ONLY").is_empty():
		assert_lt(t[0], 1.0, "well inside GEN-11's 1 ms cell budget even so")
