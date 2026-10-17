extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-05: never a knock-off with a gate open or a conscious miner outside base camp. The host's word
## is checked again that tick: refused in plain words, nothing happens (no freeze, no save, the run
## goes on), and the next try once the crew is in succeeds.

const K = preload("res://tests/unit/modes/knock_off_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_gate_open_or_a_miner_out_refuses_it() -> void:
	K.S.clear(5021)
	var s: Scenario = make(K.cfg(5021))
	K.camp(s)
	var ann: MinerHandle = K.miner(s, "ann", 0)
	K.miner(s, "bob", 1)
	s.step(2)
	K.C.shut_all(s, false)
	s.step(1)
	var tick: int = s.run.tick
	var why: String = K.knock_off(s)
	assert_eq(why, "Every gate must be shut.", "refused in plain words")
	assert_false(s.run.frozen, "nothing happens")
	assert_eq(s.run.saves.written.size(), 0, "no save")
	s.step(3)
	assert_eq(s.run.tick, tick + 3, "the run goes on")
	K.C.shut_all(s, true)
	var out: Vector2i = K.outside(s)
	s.run.movement.place(s.run, ann.entity_id, Vector2(out) + Vector2(0.5, 0.5))
	s.step(1)
	assert_eq(K.knock_off(s), "Everyone must be inside base camp.")
	assert_false(s.run.frozen)
	s.run.movement.place(s.run, ann.entity_id, Vector2(K.floor_tiles(s)[3]) + Vector2(0.5, 0.5))
	s.step(1)
	assert_eq(K.knock_off(s), "", "the crew in, the gates shut: knocked off")
	assert_true(s.run.frozen)
	assert_eq(str(s.run.saves.written[s.run.saves.written.size() - 1]["kind"]), "knockoff")
