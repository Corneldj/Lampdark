extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-04 (Gameplay §3.3, §13.9): who may take a place. A Hired Hand, a Hand-driven dropped miner or
## Bess never takes one (an injected input is refused and logged); nor a miner Grabbed or carrying
## two-handed; and one miner never holds two places (at the shared work, nor H and P at once).

const J = preload("res://tests/unit/lift/job_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _whys(s: Scenario) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in s.run.two_miner.refused:
		out.append(str(r["why"]))
	return out


func test_hands_and_bess_never_take_a_place() -> void:
	var s: Scenario = make({"seed": 2201, "fixture": J.room()})
	var events: Array = []
	var job: PairedWork = J.paired_work(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.A_TILE, Vector2i(0, 1))
	var hand: MinerHandle = J.beside(s, "hand", J.B_TILE, Vector2i(0, 1))
	# Bob, a second human idle across the room: the crew is not alone, so A needs B.
	J.beside(s, "bob", Vector2i(12, 4), Vector2i(0, 1))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.step(10)
	# The Hand's input is injected as if it held interact at the gear.
	J.hold(s, hand, 40)
	J.hold(s, ann, 40)
	s.step(40)
	assert_eq(job.place_b.holder, 0, "the Hand never took B")
	assert_true(_whys(s).has("a hand"), "refused and logged")
	assert_eq(job.progress, 0.0, "so Ann's end alone makes no progress in a crew")
	var bess: SimEntity = s.run.registry.create(WorldIds.EntityKind.BESS, J.centre(J.B_TILE) + Vector2(0, 1))
	assert_false(s.run.two_miner.take(s.run, job.place_b, bess.id), "Bess never takes a place")
	assert_true(_whys(s).has("not a miner"))


func test_one_miner_never_holds_two_places() -> void:
	var s: Scenario = make({"seed": 2202, "fixture": J.room()})
	var events: Array = []
	var job: PairedWork = J.paired_work(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.A_TILE, Vector2i(0, 1))
	J.beside(s, "bob", Vector2i(12, 4), Vector2i(0, 1))
	s.step(10)
	J.hold(s, ann, 40)
	s.step(20)
	assert_eq(job.place_a.holder, ann.entity_id)
	assert_false(s.run.two_miner.take(s.run, job.place_b, ann.entity_id), "not B as well")
	assert_true(_whys(s).has("one place"))
	# At a cue-and-press job, the holder pressing P changes nothing.
	var s2: Scenario = make({"seed": 2203, "fixture": J.room()})
	var events2: Array = []
	var cp: CuePress = J.cue_press(s2, events2, 0.0, J.LONE_H, J.LONE_P)
	var cat: MinerHandle = J.lone(s2, "cat")
	J.beside(s2, "dan", Vector2i(12, 2), Vector2i(0, 1))
	s2.step(10)
	J.hold(s2, cat, 200)
	s2.step(30)
	# Still holding the trip, Cat turns to the switch: her held interact is no press at P.
	cat.at(s2.run.tick).face(0.0)
	s2.step(60)
	assert_eq(cp.holder_place.holder, cat.entity_id, "turned, Cat still holds the trip")
	assert_false(J.whats(events2).has("success"), "and never threw the switch herself")
	assert_eq(J.whats(events2), ["cue", "miss:late"] as Array[String], "Dan never pressed: the cue ran out")


func test_the_grabbed_and_the_two_handed_never_take_a_place() -> void:
	var s: Scenario = make({"seed": 2204, "fixture": J.room()})
	var events: Array = []
	var job: PairedWork = J.paired_work(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.A_TILE, Vector2i(0, 1))
	var bob: MinerHandle = J.beside(s, "bob", J.B_TILE, Vector2i(0, 1))
	s.step(10)
	assert_true(s.run.inventory.begin_two_handed(s.run, bob.entity_id), "Bob takes a load in both hands")
	assert_false(s.run.two_miner.take(s.run, job.place_b, bob.entity_id))
	assert_true(_whys(s).has("no free hand"))
	J.hold(s, ann, 30)
	s.step(10)
	assert_eq(job.place_a.holder, ann.entity_id)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(3)
	assert_eq(job.place_a.holder, 0, "a fall lets go at once")


func test_a_dropped_players_hand_driven_miner_never_takes_a_place() -> void:
	var s: Scenario = make({"seed": 2205, "fixture": J.room()})
	var events: Array = []
	var job: PairedWork = J.paired_work(s, events)
	J.beside(s, "ann", J.A_TILE, Vector2i(0, 1))
	var bob: MinerHandle = J.beside(s, "bob", J.B_TILE, Vector2i(0, 1))
	s.step(10)
	assert_true(s.run.drops.remove_player(s.run, "bob", "kicked", DropHandler.Takeover.KICKED))
	s.step(5)
	assert_true(s.run.drops.hand_driven.has(bob.entity_id), "a Hand drives Bob's miner")
	assert_false(s.run.two_miner.take(s.run, job.place_b, bob.entity_id))
	assert_true(_whys(s).has("a hand"), "refused and logged")
