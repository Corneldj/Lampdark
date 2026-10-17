extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9): a Hand coughs every three minutes or so (hands.cough_interval_s, ±
## hands.cough_jitter_s), at 12 np from where it stands, whatever the orders ('Quiet!' included),
## and never while unconscious. The schedule comes from the Hand's own named stream (FND-06's
## "hands"), so the same seed coughs at the same ticks; FND-08's freeze_ai holds it, and thawing
## moves it on by the frozen ticks.

const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _coughs(run_seed: int, minutes: float, quiet: bool = false) -> Array[int]:
	var s: Scenario = make({"seed": run_seed, "fixture": HW.road(20)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0, false)
	var hand: int = HW.hand(s, a + Vector2i(4, 0))
	if quiet:
		ann.at(s.run.tick).callout("quiet", CalloutLines.WHISPER)
	s.step(roundi(minutes * 60.0 * Tuning.f(&"net.tick_hz")))
	var ticks: Array[int] = []
	for e: HandController.Hand in [HW.h_of(s, hand)]:
		assert_eq(e.entity, hand)
	for ev: NoiseSystem.Event in s.run.noise.event_log:
		if ev.type == NoiseTypes.Type.COUGH and ev.source_entity == hand:
			assert_eq(ev.level_np, 12.0, "at 12 np")
			ticks.append(ev.tick)
	return ticks


func test_every_three_minutes_or_so() -> void:
	var ticks: Array[int] = _coughs(4841, 13.0)
	gut.p("coughs at %s" % [ticks])
	assert_gte(ticks.size(), 3)
	var hz: float = Tuning.f(&"net.tick_hz")
	var lo: float = Tuning.f(&"hands.cough_interval_s") - Tuning.f(&"hands.cough_jitter_s")
	var hi: float = Tuning.f(&"hands.cough_interval_s") + Tuning.f(&"hands.cough_jitter_s")
	for i: int in range(1, ticks.size()):
		var gap: float = (ticks[i] - ticks[i - 1]) / hz
		assert_between(gap, lo, hi, "a gap of %.0f s" % gap)
	assert_eq(_coughs(4841, 13.0), ticks, "the same seed, the same coughs")


func test_quiet_never_stops_it() -> void:
	assert_gte(_coughs(4842, 7.5, true).size(), 2, "it coughs whatever the orders")


func test_never_while_unconscious_and_held_by_freeze_ai() -> void:
	var s: Scenario = make({"seed": 4843, "fixture": HW.road(20)})
	var a: Vector2i = s.fixture.spot("a")
	HW.human(s, "ann", a, 0.0, false)
	var hand: int = HW.hand(s, a + Vector2i(4, 0))
	var h: HandController.Hand = HW.h_of(s, hand)
	var due: int = h.next_cough
	s.run.creatures.set_frozen(s.run, true)
	s.step(due - s.run.tick + 200)
	assert_eq(s.run.hands.coughs.size(), 0, "freeze_ai holds the cough")
	var frozen_for: int = s.run.tick - 0
	s.run.creatures.set_frozen(s.run, false)
	s.step(1)
	assert_gt(h.next_cough, due, "thawing moves it on by the frozen ticks")
	assert_true(s.run.falls.fall_unconscious(s.run, hand, FallCause.Cause.ROOF_FALL))
	s.step(h.next_cough - s.run.tick + 20)
	assert_eq(s.run.hands.coughs.size(), 0, "no cough while unconscious")
	assert_gt(frozen_for, 0)
