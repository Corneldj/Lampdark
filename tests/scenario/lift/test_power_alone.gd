extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-05 alone (Gameplay §3.3, §11.11): a lone human (a public lobby's only human beside a Hired
## Hand) holds the trip, lets go, turns and throws the switch inside LFT-04's 3 s hold-over, and
## power comes on. With a second human conscious, the same throw after letting go misses and power
## stays off.

const P = preload("res://tests/unit/lift/power_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _ready_to_throw(run_seed: int) -> Scenario:
	var s: Scenario = make({"seed": run_seed, "fixture": P.room(), "mode": ServerConfig.Mode.PUBLIC})
	P.substation(s, true)
	s.run.power.links_cleared = true
	s.run.power.fuses_fitted = s.run.power.fuses_required()
	s.step(2)
	return s


## Ann on the spot between the trip (west) and the switch (east): holds the trip 1 s, lets go, turns
## east and throws 2 s later.
func _hold_let_go_throw(s: Scenario, ann: MinerHandle) -> void:
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 20)
	var let_go: int = s.run.tick + 20
	ann.at(let_go + 4).face(0.0)
	ann.at(let_go + 40).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(let_go + 80 - s.run.tick)


func test_a_lone_human_throws_the_switch_alone() -> void:
	var s: Scenario = _ready_to_throw(5521)
	assert_not_null(s.run.power.main_switch)
	var ann: MinerHandle = s.add_miner("ann", P.LONE_SPOT, {"facing_deg": 180.0})
	ann.at(s.run.tick).face(180.0)
	ann.brain = null
	var hand: MinerHandle = s.add_miner("hand", Vector2i(3, 2))
	hand.brain = null
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.step(10)
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "the only human: a lone human")
	_hold_let_go_throw(s, ann)
	assert_true(s.run.power.is_on(), "held, let go, thrown within the hold-over")
	assert_true(s.run.repair.is_done(&"power"))


func test_with_a_second_human_the_trip_goes_when_let_go() -> void:
	var s: Scenario = _ready_to_throw(5522)
	var ann: MinerHandle = s.add_miner("ann", P.LONE_SPOT, {"facing_deg": 180.0})
	ann.at(s.run.tick).face(180.0)
	ann.brain = null
	var bob: MinerHandle = s.add_miner("bob", Vector2i(3, 2))
	bob.brain = null
	s.step(10)
	assert_false(AloneRules.is_alone(s.run, ann.entity_id))
	_hold_let_go_throw(s, ann)
	assert_false(s.run.power.is_on(), "in a crew the trip goes when let go: the throw misses")
	assert_true(P.whats(s.run.power).has("miss"))
