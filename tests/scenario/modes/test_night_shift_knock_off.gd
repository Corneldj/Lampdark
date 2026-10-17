extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-05: Night Shift knocks off as friends do, with one member and an immediate acknowledgement;
## the save resumes with its one player, nobody absent, from the moment it was saved.

const K = preload("res://tests/unit/modes/knock_off_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_night_shift_knocks_off_and_resumes() -> void:
	K.S.clear(5031)
	var s: Scenario = make(K.cfg(5031, ServerConfig.Mode.NIGHTSHIFT))
	K.camp(s)
	var ann: MinerHandle = K.miner(s, "ann", 0)
	K.S.L.lit_in_hand(s, ann)
	s.step(3)
	assert_true(s.run.knock_off.available)
	var tick: int = s.run.tick
	assert_eq(K.knock_off(s), "")
	assert_eq(int(Variants.number(s.run.saves.acks.get(ann.slot, -1))), s.run.knock_off.awaiting_seq, "her one acknowledgement")
	assert_eq(ann.connection.reject_reason, Protocol.Reject.KNOCKED_OFF)
	var path: String = K.knockoff_path(s)
	K.S.kill(s)
	var b: Scenario = K.resume(make, 5031, path, ServerConfig.Mode.NIGHTSHIFT)[0]
	assert_eq(b.run.tick, tick)
	var back: MinerHandle = b.rejoin("ann")
	assert_eq(b.run.absent.park_absent(b.run), 0, "nobody absent")
	b.step(5)
	assert_eq(back.entity_id, ann.entity_id, "her own miner")
	assert_not_null(b.run.lamps.lamp_in_hand(back.entity_id), "with her lamp")
	assert_eq(b.run.tick, tick + 5, "the run goes on")
