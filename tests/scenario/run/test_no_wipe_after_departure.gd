extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 (Gameplay §3.6, §3.8): once the cage has gone, nothing below can wipe the run. Bob, left
## below, falls during the ride: no wipe; the run ends at the surface, Ann Escaped and Bob Left Below.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_falls_below_never_wipe_after_departure() -> void:
	var s: Scenario = make({"seed": 11301, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var bob: MinerHandle = K.aboard(s, "bob", 1)
	K.pull(s, ann)
	K.pull(s, bob)
	K.move_to(s, bob, s.run.base_camp.medbay_tables()[0])
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.is_departed(), K.bell_ticks() + 10))
	# Ann aboard is knocked down too: below and above, nobody conscious, and still no wipe.
	s.run.miner_state.fall_unconscious(bob.entity_id, "test")
	s.run.miner_state.fall_unconscious(ann.entity_id, "test")
	s.step(40)
	assert_false(s.run.outcomes.ended, "no wipe after departure")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return s.run.outcomes.ended, ShaftRide.ride_ticks() + 10), "the run ends at the surface")
	assert_false(Variants.flag(s.run.outcomes.record["wipe"]))
	var by: Dictionary = {}
	for raw: Variant in Variants.array(s.run.outcomes.record["miners"]):
		by[int(Variants.number(Variants.dict(raw)["miner_id"]))] = str(Variants.dict(raw)["outcome"])
	assert_eq(str(by[ann.entity_id]), "escaped", "carried unconscious, she came up")
	assert_eq(str(by[bob.entity_id]), "left_below")
