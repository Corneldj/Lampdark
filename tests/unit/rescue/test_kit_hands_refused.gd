extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-02 (§13.9): a Hand-controlled miner can never start a kit use (server-side, whatever asks),
## and a Hand's body on a table can be revived by a human.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const M = preload("res://tests/unit/rescue/medbay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = M.beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	M.lay(s, bob.entity_id, table)
	s.step(1)
	return [s, ann, bob]


func test_a_hand_never_uses_a_kit() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var hand: int = ann.entity_id
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand
	M.give_kit(s, ann.entity_id)
	assert_false(s.run.revival.may_use(s.run, ann.entity_id))
	var offered: Array[String] = s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id)
	assert_false(offered.has("revive") or offered.has("cure"), "never offered")
	var a: TimedAction = M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 110)
	s.step(105)
	assert_false(a.done and M.life(s, bob.entity_id) == MinerTransitions.Life.UPRIGHT, "refused server-side")
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(M.kits(s, ann.entity_id), 1)
	# Nor from the belt, on herself.
	ann.at(s.run.tick).select_slot(0).hold(InputRecord.HOLD_USE, 110)
	s.step(110)
	assert_eq(M.kits(s, ann.entity_id), 1)


func test_a_hands_body_is_revived_by_a_human() -> void:
	var parts: Array = _setup(2)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var hand: int = bob.entity_id
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand
	M.give_kit(s, ann.entity_id)
	assert_true(s.run.revival.may_revive(s.run, ann.entity_id, bob.entity_id))
	M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 110)
	s.step(105)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UPRIGHT)
