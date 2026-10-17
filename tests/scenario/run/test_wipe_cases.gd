extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 (Gameplay §3.8, §11.11, §13.7, §13.9): three wipes.
## - A crew of four on the road all fall: the run ends on the last fall's tick, every miner Left
##   Below, the map table frozen for the card.
## - Night Shift: alone, her first fall waits for her self-revive; the second, with it spent, is the
##   solo wipe, on the tick RSC-09 calls it.
## - A lone human with two Hired Hands: the Hands standing never keep the run alive.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _crew(run_seed: int, names: Array[String], mode: ServerConfig.Mode) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": D.hall(), "mode": mode, "slots": 6})
	var spots: Array[String] = ["a", "b", "c", "d", "e", "f"]
	var out: Array[MinerHandle] = []
	for i: int in names.size():
		out.append(s.add_miner(names[i], s.fixture.spot(spots[i])))
	s.step(2)
	return [s, out]


func test_a_crew_falls_to_the_last() -> void:
	var r: Array = _crew(11201, ["ann", "bob", "cid", "dot"] as Array[String], ServerConfig.Mode.FRIENDS)
	var s: Scenario = r[0]
	var crew: Array[MinerHandle] = r[1]
	for i: int in crew.size():
		s.run.miner_state.fall_unconscious(crew[i].entity_id, "test")
		s.step(40)
		assert_eq(s.run.outcomes.ended, i == crew.size() - 1, "after %d of 4" % (i + 1))
	var rec: Dictionary = s.run.outcomes.record
	assert_true(Variants.flag(rec["wipe"]))
	assert_eq(int(Variants.number(rec["up_count"])), 0, "Up none of 4")
	assert_eq(int(Variants.number(rec["crew_size"])), 4)
	if s.run.sheets != null and s.run.sheets.table != null:
		assert_true(s.run.sheets.table.frozen, "the map table frozen for the card")
	assert_true(s.run.saves.closed, "the save chain closed")


func test_night_shift_waits_for_the_self_revive() -> void:
	var r: Array = _crew(11202, ["nell"] as Array[String], ServerConfig.Mode.NIGHTSHIFT)
	var s: Scenario = r[0]
	var nell: MinerHandle = r[1][0]
	var wiped_at: Array[int] = [-1]
	s.run.self_revive.wiped.connect(func(_m: int, tick: int) -> void: wiped_at[0] = tick)
	s.run.miner_state.fall_unconscious(nell.entity_id, "test")
	s.step(3)
	assert_false(s.run.outcomes.ended, "her self-revive pending")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.miner_state.life(nell.entity_id) == MinerTransitions.Life.UPRIGHT,
		roundi((Tuning.f(&"rescue.self_revive_delay_s") + 2.0) * Tuning.f(&"net.tick_hz"))))
	s.step(20)
	s.run.miner_state.fall_unconscious(nell.entity_id, "test")
	s.step(3)
	assert_true(s.run.outcomes.ended, "with it spent, the solo wipe")
	assert_eq(s.run.outcomes.ended_tick, wiped_at[0], "on the tick RSC-09 calls it")
	var nell_row: Dictionary = Variants.dict(Variants.array(s.run.outcomes.record["miners"])[0])
	assert_true(Variants.flag(nell_row["solo_rules"]), "under the solo rules")


func test_a_lone_human_with_hands() -> void:
	var s: Scenario = make({"seed": 11203, "fixture": D.hall(), "mode": ServerConfig.Mode.FRIENDS})
	# The Hands are known before the first count: the run began with one human.
	var crew: Array[MinerHandle] = [s.add_miner("ann", s.fixture.spot("a")), s.add_miner("hal", s.fixture.spot("b")),
		s.add_miner("hob", s.fixture.spot("c"))]
	var hands: Array[int] = [crew[1].entity_id, crew[2].entity_id]
	s.run.crew.is_hired_hand = func(e: int) -> bool: return hands.has(e)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e)
	s.step(2)
	s.run.miner_state.fall_unconscious(crew[0].entity_id, "test")
	s.step(3)
	assert_false(s.run.outcomes.ended, "alone with Hands, her self-revive first")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.miner_state.life(crew[0].entity_id) == MinerTransitions.Life.UPRIGHT,
		roundi((Tuning.f(&"rescue.self_revive_delay_s") + 2.0) * Tuning.f(&"net.tick_hz"))))
	s.step(20)
	s.run.miner_state.fall_unconscious(crew[0].entity_id, "test")
	s.step(3)
	assert_true(s.run.outcomes.ended, "the Hands standing keep nothing alive")
	assert_eq(int(Variants.number(s.run.outcomes.record["crew_size"])), 1)
