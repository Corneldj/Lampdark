extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03's self-rescue: never offered while another conscious human is in the mine; offered once
## per grab to the alone; 50% +/- 1.5% over 10,000 seeded rolls; the same seed, the same results;
## releasing early spends nothing.

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_odds_and_determinism() -> void:
	var s: Scenario = make({"seed": 8, "fixture": H.hall()})
	var won: int = 0
	var first: PackedByteArray = PackedByteArray()
	for i: int in 10000:
		var ok: bool = SelfRescue.roll(s.run, 1000 + i % 7, i)
		won += 1 if ok else 0
		first.append(1 if ok else 0)
	var share: float = won / 10000.0
	gut.p("self-rescue: %d of 10,000 succeeded (%.2f%%)" % [won, share * 100.0])
	assert_between(share, 0.485, 0.515)
	var again: Scenario = make({"seed": 8, "fixture": H.hall()})
	var second: PackedByteArray = PackedByteArray()
	for i: int in 10000:
		second.append(1 if SelfRescue.roll(again.run, 1000 + i % 7, i) else 0)
	assert_eq(second, first, "the same seed, the same results")


func test_offered_only_when_alone_and_once() -> void:
	var s: Scenario = make({"seed": 9, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	s.step(2)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 2000)
	s.step(1)
	var g: GrabHold = s.run.holds.grabs[id]
	assert_false(SelfRescue.offered(s.run, g), "another conscious human: never offered")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	s.step(80)
	assert_false(g.rescue_spent)
	assert_eq(g.state, GrabHold.State.ACTIVE)
	s.run.miner_state.fall_unconscious(bob.entity_id, "test")
	s.step(2)
	assert_true(SelfRescue.offered(s.run, g), "the last conscious of a crew of two: offered")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 20)
	s.step(25)
	assert_false(g.rescue_spent, "released after 1 s: nothing spent")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 45)
	s.step(50)
	assert_true(g.rescue_spent, "held 2 s: the attempt is spent")
	assert_false(SelfRescue.offered(s.run, g), "once per grab")
	var logged: Array = s.run.holds.events.filter(func(e: Dictionary) -> bool: return e["type"] == &"self_rescue")
	assert_eq(logged.size(), 1)
	var success: bool = Variants.flag(Variants.dict(logged[0])["success"])
	s.step(2)
	assert_eq(g.state == GrabHold.State.ENDED, success, "success frees; failure lets the grab run on")
