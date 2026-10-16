extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03's self-rescue as the struggle (Proposed after the first playtest): anyone in a Tapper's pin
## may struggle, in a Stythe's drag only a miner alone, never a Hand; presses are judged at the shown
## tick; rescue.struggle_hits presses inside the zone break the grab free; a miss shrinks the zone,
## rattles and locks presses out; the zones come from the seeded stream, the same seed the same.

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _pair(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	ann.brain = null
	bob.brain = null
	s.step(2)
	return [s, ann, bob]


## A tick at which the needle is at the middle of the zone, at or after `from`.
static func _in_zone_tick(k: SelfRescue.Check, from: int) -> int:
	for t: int in range(from, from + SelfRescue.sweep_ticks() + 1):
		if SelfRescue.in_zone(k, SelfRescue.needle_deg(k, t)) and SelfRescue.in_zone(k, SelfRescue.needle_deg(k, t) - 5.0):
			return t
	return -1


static func _out_of_zone_tick(k: SelfRescue.Check, from: int) -> int:
	for t: int in range(from, from + SelfRescue.sweep_ticks() + 1):
		if not SelfRescue.in_zone(k, SelfRescue.needle_deg(k, t)):
			return t
	return -1


func test_who_may_struggle() -> void:
	var w: Array = _pair(9)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var pin: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 2000)
	s.step(1)
	var pinned: GrabHold = s.run.holds.grabs[pin]
	assert_true(SelfRescue.offered(s.run, pinned), "a pin: anyone struggles, a teammate beside her or not")
	assert_not_null(s.run.holds.self_rescue.check_of(pin), "its check is open")
	s.run.holds.end_grab(s.run, pin, GrabHold.Outcome.BROKEN)
	s.step(2)
	var drag: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.STYTHE_DRAG, 98, 2000)
	s.step(1)
	var g: GrabHold = s.run.holds.grabs[drag]
	assert_false(SelfRescue.offered(s.run, g), "a drag with a conscious teammate: never")
	s.run.miner_state.fall_unconscious(bob.entity_id, "test")
	s.step(2)
	assert_true(SelfRescue.offered(s.run, g), "a drag, the last conscious of a crew of two: offered")
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	assert_false(SelfRescue.offered(s.run, g), "never a Hand")


func test_three_hits_in_the_zone_break_free() -> void:
	var w: Array = _pair(10)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 2000)
	s.step(1)
	var g: GrabHold = s.run.holds.grabs[id]
	var k: SelfRescue.Check = s.run.holds.self_rescue.check_of(id)
	var needed: int = Tuning.i(&"rescue.struggle_hits")
	assert_eq(needed, 3)
	for i: int in needed:
		var t: int = _in_zone_tick(k, s.run.tick)
		assert_ne(t, -1, "the zone comes round")
		s.step(maxi(0, t - s.run.tick))
		var before: float = k.zone_start
		s.run.holds.self_rescue.press(s.run, s.run.holds, g, k, t)
		if i < needed - 1:
			assert_eq(k.hits, i + 1, "hit %d" % (i + 1))
			assert_ne(k.zone_start, before, "the zone moves on")
	s.step(2)
	assert_eq(g.state, GrabHold.State.ENDED, "free")
	assert_eq(g.outcome, GrabHold.Outcome.SELF_RESCUED)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UPRIGHT)


func test_a_miss_shrinks_rattles_and_locks_out() -> void:
	var w: Array = _pair(11)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 2000)
	s.step(1)
	var g: GrabHold = s.run.holds.grabs[id]
	var k: SelfRescue.Check = s.run.holds.self_rescue.check_of(id)
	var size: float = k.zone_size
	var events: int = s.run.noise.event_log.size()
	var t: int = _out_of_zone_tick(k, s.run.tick)
	s.step(maxi(0, t - s.run.tick))
	s.run.holds.self_rescue.press(s.run, s.run.holds, g, k, t)
	assert_almost_eq(k.zone_size, size - Tuning.f(&"rescue.struggle_zone_shrink_deg"), 1e-6, "the zone shrinks")
	s.step(2)
	var rattled: bool = false
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events):
		rattled = rattled or e.type == NoiseTypes.Type.STRUGGLE
	assert_true(rattled, "a miss rattles")
	var inside: int = _in_zone_tick(k, s.run.tick)
	if inside >= 0 and inside < k.lockout_until:
		s.run.holds.self_rescue.press(s.run, s.run.holds, g, k, inside)
		assert_eq(k.hits, 0, "a press in the lockout counts for nothing: no mashing")
	for _i: int in 10:
		k.lockout_until = -1
		s.run.holds.self_rescue.press(s.run, s.run.holds, g, k, _out_of_zone_tick(k, s.run.tick))
	assert_almost_eq(k.zone_size, Tuning.f(&"rescue.struggle_zone_min_deg"), 1e-6, "never smaller than the floor")


func test_presses_are_judged_at_the_shown_tick() -> void:
	var w: Array = _pair(12)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 2000)
	s.step(1)
	var g: GrabHold = s.run.holds.grabs[id]
	var k: SelfRescue.Check = s.run.holds.self_rescue.check_of(id)
	var t: int = _in_zone_tick(k, s.run.tick)
	s.step(maxi(0, t - s.run.tick) + 4)  # the press arrives 4 ticks late, the needle long gone
	s.run.holds.self_rescue.press(s.run, s.run.holds, g, k, t)
	assert_eq(k.hits, 1, "judged where the needle was on her screen, not on arrival")


func test_the_same_seed_the_same_zones() -> void:
	var zones: Array[float] = []
	for _run: int in 2:
		var w: Array = _pair(13)
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1]
		var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 2000)
		s.step(1)
		zones.append(s.run.holds.self_rescue.check_of(id).zone_start)
	assert_eq(zones[0], zones[1])
