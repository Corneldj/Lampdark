extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04: over 1,000 seeded draws every gap between windows lies within rescue.coming_round_interval_s
## (60-120 s); each window lasts exactly rescue.coming_round_window_s (160 ticks), and the next gap is
## measured from its end (Proposed). The dead get no windows.

const D = preload("res://tests/scenario/rescue/dark_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_thousand_gaps_within_the_band() -> void:
	var s: Scenario = make({"seed": 501, "fixture": "test"})
	var hz: float = Tuning.f(&"net.tick_hz")
	var lo: int = roundi(60.0 * hz)
	var hi: int = roundi(120.0 * hz)
	var seen_lo: int = hi
	var seen_hi: int = lo
	for i: int in 1000:
		var f: DarkSystem.Fallen = DarkSystem.Fallen.new()
		f.rng = s.run.stream(HashDomain.RESCUE_COMING_ROUND, PackedInt64Array([1000 + i]))
		var gap: int = s.run.dark._gap(f)
		assert_between(gap, lo, hi)
		seen_lo = mini(seen_lo, gap)
		seen_hi = maxi(seen_hi, gap)
	gut.p("gaps %d..%d ticks" % [seen_lo, seen_hi])
	assert_lt(seen_lo, lo + 60, "the band's low end is reached")
	assert_gt(seen_hi, hi - 60, "and its high end")


func test_windows_last_160_ticks_and_gaps_run_from_their_end() -> void:
	var s: Scenario = make({"seed": 502, "fixture": "test", "overrides": D.SHORT})
	var miners: Array[MinerHandle] = D.W.crew(s, 2, 502)
	s.step(5)
	D.fall(s, miners[0])
	s.step(60 * 20)
	var log: Array[Dictionary] = s.run.dark.windows_log
	assert_gte(log.size(), 3, "several windows in a minute of short spells")
	for i: int in log.size():
		var w: Dictionary = log[i]
		var opened: int = w["open"]
		var closed: int = w["close"]
		assert_eq(closed - opened, 160, "8 s exactly")
		if i > 0:
			var before: int = Variants.dict(log[i - 1])["close"]
			var gap: int = opened - before
			assert_between(gap, 60, 100, "from the last window's end, within the short spell")
	s.run.miner_state.kill(miners[0].entity_id, "test")
	s.step(1)
	var n: int = log.size()
	s.step(30 * 20)
	assert_eq(s.run.dark.windows_log.size(), n, "the dead get no windows")
