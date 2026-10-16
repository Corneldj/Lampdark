extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01's once-only rules (Gameplay §10.1): a re-struck pin is the same grab (+25 once); one trap
## adds +15 once, even if its miner is pinned and freed while still in it; a creature seen, unseen
## for 9.9 s and seen again adds nothing, and after 10 s unseen it adds +10 again.

const D = preload("res://tests/scenario/director/draught_world.gd")
const W = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run(seed_value: int) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": D.hall(), "director": true})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("c"), {"facing_deg": 0.0})
	D.stand_in(s)
	s.step(2)
	return [s, ann]


func test_a_pin_re_struck_adds_25_once() -> void:
	var w: Array = _run(401)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var pin: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 500)
	assert_gt(pin, 0)
	s.step(2)
	assert_eq(s.state.intensity(ann), 25.0, "the pin: +25")
	# The silent pull frees her; the Tapper re-strikes: the same grab goes on (RSC-03).
	assert_true(s.run.holds.suspend(s.run, pin))
	s.step(2)
	assert_true(s.run.holds.resume(s.run, pin))
	s.step(2)
	assert_eq(s.state.intensity(ann), 25.0, "a re-strike on the same pin adds nothing")
	# Even were the grab announced again, its id is counted.
	s.run.holds.grab_begun.emit(pin, GrabHold.Kind.TAPPER_PIN, 0, ann.entity_id)
	s.step(1)
	assert_eq(s.state.intensity(ann), 25.0, "the same grab, once")


func test_one_trap_adds_15_once_even_through_a_pin() -> void:
	var w: Array = _run(402)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	assert_true(s.run.holds.catch(s.run, ann.entity_id, CaughtHold.Kind.MAN_TRAP, 9))
	s.step(2)
	assert_eq(s.state.intensity(ann), 15.0, "caught: +15")
	# Pinned while in it (a new grab, +25), and freed from the pin, still in the trap.
	var pin: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 500)
	assert_gt(pin, 0)
	s.step(2)
	assert_eq(s.state.intensity(ann), 40.0, "the pin is a grab of its own")
	assert_true(s.run.holds.end_grab(s.run, pin, GrabHold.Outcome.BROKEN))
	s.step(2)
	assert_not_null(s.run.holds.caught_in(ann.entity_id), "still in the trap")
	s.run.holds.caught_begun.emit(9, CaughtHold.Kind.MAN_TRAP, ann.entity_id)
	s.step(1)
	assert_eq(s.state.intensity(ann), 40.0, "the same trap adds nothing again")


## A stand-in Stythe 4 tiles ahead under a lamp; Ann's eyes shut and opened (VIS-03's blinding)
## take it out of her seen set and back.
func test_a_creature_seen_again_after_9_9_s_adds_nothing_after_10_s_adds_10() -> void:
	var w: Array = _run(403)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var at: Vector2i = s.fixture.spot("c") + Vector2i(4, 0)
	assert_gt(s.place_stand_in(WorldIds.EntityKind.STYTHE, at), 0)
	W.lamp(s, Vector2(at) + Vector2(0.5, 0.5), 3.0)
	s.step(3)
	assert_eq(s.state.intensity(ann), 10.0, "first sight: +10")
	var hz: float = Tuning.f(&"net.tick_hz")
	var again: int = roundi(Tuning.f(&"director.creature_reseen_after_s") * hz)
	# Unseen for 9.9 s (198 ticks), then seen: nothing.
	s.run.vision.set_blind(ann.slot, &"test", true)
	s.step(again - 2)
	s.run.vision.set_blind(ann.slot, &"test", false)
	s.step(2)
	assert_eq(s.state.intensity(ann), 10.0, "seen again after 9.9 s: nothing")
	# Unseen for 10 s, then seen: +10 again.
	s.run.vision.set_blind(ann.slot, &"test", true)
	s.step(again)
	s.run.vision.set_blind(ann.slot, &"test", false)
	s.step(2)
	assert_eq(s.state.intensity(ann), 20.0, "seen again after 10 s: +10")
