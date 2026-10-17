extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 (Gameplay §3.8, §11.11, §13.9): the wipe. When the last conscious counted miner falls before
## the cage leaves, the run ends that tick with every miner Left Below and an up count of 0, once.
## Caught and Grabbed are conscious. Hired Hands never count, so four fallen miners and two standing
## Hands is a wipe; a Hand-driven dropped miner does count. An absent player's waiting miner never
## counts and takes no outcome (MOD-05's to decide). A pending self-revive defers it (RSC-09): alone
## in Night Shift, the first fall waits for the self-revive, and a fall with it spent wipes.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _crew(run_seed: int, names: Array[String], mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": D.hall(), "mode": mode, "slots": 6})
	var spots: Array[String] = ["a", "b", "c", "d", "e", "f"]
	var out: Array[MinerHandle] = []
	for i: int in names.size():
		out.append(s.add_miner(names[i], s.fixture.spot(spots[i])))
	s.step(2)
	return [s, out]


func _ended(s: Scenario) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	s.run.outcomes.run_ended.connect(func(rec: Dictionary) -> void: out.append(rec))
	return out


func test_the_last_fall_wipes_the_run_that_tick() -> void:
	var r: Array = _crew(11001, ["ann", "bob", "cid"] as Array[String])
	var s: Scenario = r[0]
	var crew: Array[MinerHandle] = r[1]
	var ended: Array[Dictionary] = _ended(s)
	s.run.miner_state.fall_unconscious(crew[0].entity_id, "test")
	s.run.miner_state.fall_unconscious(crew[1].entity_id, "test")
	s.step(3)
	assert_false(s.run.outcomes.ended, "one still standing")
	s.run.miner_state.fall_unconscious(crew[2].entity_id, "test")
	var fell_at: int = s.run.tick
	s.step(1)
	assert_true(s.run.outcomes.ended, "the last fall wipes it")
	assert_eq(s.run.outcomes.ended_tick, fell_at, "that tick")
	assert_eq(ended.size(), 1)
	var rec: Dictionary = ended[0]
	assert_true(Variants.flag(rec["wipe"]))
	assert_eq(int(Variants.number(rec["up_count"])), 0, "Up none of 3")
	assert_eq(int(Variants.number(rec["crew_size"])), 3)
	for raw: Variant in Variants.array(rec["miners"]):
		assert_eq(str(Variants.dict(raw)["outcome"]), "left_below")
	s.step(1)
	for h: MinerHandle in crew:
		assert_eq(s.run.miner_state.miner(h.entity_id).outcome, MinerTransitions.Outcome.LEFT_BELOW, "set on the miner")
	s.step(20)
	assert_eq(ended.size(), 1, "once")


func test_caught_and_grabbed_are_conscious() -> void:
	var r: Array = _crew(11002, ["ann", "bob", "cid"] as Array[String])
	var s: Scenario = r[0]
	var crew: Array[MinerHandle] = r[1]
	s.run.miner_state.fall_unconscious(crew[0].entity_id, "test")
	s.run.miner_state.enter_caught(crew[1].entity_id, &"man_trap", 1)
	s.run.miner_state.enter_grabbed(crew[2].entity_id, &"tapper_pin", 99)
	s.step(5)
	assert_eq(s.run.miner_state.life(crew[1].entity_id), MinerTransitions.Life.CAUGHT)
	assert_eq(s.run.miner_state.life(crew[2].entity_id), MinerTransitions.Life.GRABBED)
	assert_false(s.run.outcomes.ended, "a hold is conscious: no wipe")


func test_hired_hands_never_count_but_a_dropped_miner_does() -> void:
	var r: Array = _crew(11003, ["ann", "bob", "cid", "dot", "hal", "hob"] as Array[String])
	var s: Scenario = r[0]
	var crew: Array[MinerHandle] = r[1]
	var hands: Array[int] = [crew[4].entity_id, crew[5].entity_id]
	s.run.crew.is_hired_hand = func(e: int) -> bool: return hands.has(e)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e) or e == crew[3].entity_id
	for i: int in 3:
		s.run.miner_state.fall_unconscious(crew[i].entity_id, "test")
	s.step(3)
	assert_false(s.run.outcomes.ended, "Dot, dropped and driven by a Hand, still counts")
	s.run.miner_state.fall_unconscious(crew[3].entity_id, "test")
	s.step(2)
	assert_true(s.run.outcomes.ended, "four fallen and two standing Hands: a wipe")
	assert_eq(int(Variants.number(s.run.outcomes.record["crew_size"])), 4, "the Hands are no part of the crew")


func test_an_absent_miner_neither_counts_nor_takes_an_outcome() -> void:
	var r: Array = _crew(11005, ["ann", "bob", "cid", "dot"] as Array[String])
	var s: Scenario = r[0]
	var crew: Array[MinerHandle] = r[1]
	var dot: int = crew[3].entity_id
	s.run.crew.is_absent = func(e: int) -> bool: return e == dot
	for i: int in 3:
		s.run.miner_state.fall_unconscious(crew[i].entity_id, "test")
	s.step(3)
	assert_true(s.run.outcomes.ended, "Dot waits, conscious but out of the crew count: a wipe")
	assert_eq(int(Variants.number(s.run.outcomes.record["crew_size"])), 3)
	for raw: Variant in Variants.array(s.run.outcomes.record["miners"]):
		assert_ne(int(Variants.number(Variants.dict(raw)["miner_id"])), dot, "Dot is not in the record")
	s.step(1)
	assert_eq(s.run.miner_state.miner(dot).outcome, MinerTransitions.Outcome.NONE, "no outcome: MOD-05's to decide")
	assert_eq(s.run.miner_state.miner(crew[0].entity_id).outcome, MinerTransitions.Outcome.LEFT_BELOW)


func test_a_pending_self_revive_defers_the_wipe() -> void:
	var r: Array = _crew(11004, ["ann"] as Array[String], ServerConfig.Mode.NIGHTSHIFT)
	var s: Scenario = r[0]
	var ann: MinerHandle = r[1][0]
	s.run.miner_state.fall_unconscious(ann.entity_id, "test")
	s.step(3)
	assert_true(s.run.self_revive.deferral_active(), "her self-revive is pending")
	assert_false(s.run.outcomes.ended, "no wipe while it is")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.miner_state.life(ann.entity_id) == MinerTransitions.Life.UPRIGHT,
		roundi((Tuning.f(&"rescue.self_revive_delay_s") + 2.0) * Tuning.f(&"net.tick_hz"))), "she comes round")
	assert_false(s.run.outcomes.ended)
	s.run.miner_state.fall_unconscious(ann.entity_id, "test")
	s.step(3)
	assert_true(s.run.outcomes.ended, "alone with it spent: the solo wipe")
	assert_true(Variants.flag(s.run.outcomes.record["wipe"]))
