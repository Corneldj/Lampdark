extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09: a public run is never saved. Through a fall, a death and well past the snapshot interval
## it writes no file, journals nothing and sends no save data or journal entry to any client; its
## abnormal end voids it (STM-10 hears of it), writing nothing and recording no outcome. Cat stays
## up, so the run is still under way (the whole crew down is a wipe, LFT-11: no longer abnormal).

const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_public_run_writes_nothing_and_its_abnormal_end_voids_it() -> void:
	S.clear(921)
	var s: Scenario = make(S.cfg(921, ServerConfig.Mode.PUBLIC))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	var cat: MinerHandle = S.miner(s, "cat", Vector2i(10, 4))
	s.step(10)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(5)
	s.run.miner_state.kill(bob.entity_id, "kit")
	var interval: int = roundi(Tuning.f(&"net.snapshot_interval_s") * Tuning.f(&"net.tick_hz"))
	s.step(interval + 40)
	assert_eq(s.run.saves.written.size(), 0, "no snapshot")
	assert_eq(s.run.saves.journal.entries.size(), 0, "no journal entry")
	var voids: Array[String] = []
	s.run.saves.voided.connect(func(why: String) -> void: voids.append(why))
	assert_eq(s.run.saves.end_abnormally(s.run, "the server was killed"), {}, "nothing saved at the end")
	assert_eq(voids.size(), 1, "the run is voided")
	assert_eq(s.run.miner_state.miner(ann.entity_id).outcome, MinerTransitions.Outcome.NONE, "no outcome recorded")
	assert_false(s.run.outcomes.ended, "and the run never ends with one")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://kit_saves/921")), "no file on disk")
	for h: MinerHandle in [ann, bob, cat]:
		var save_msgs: int = 0
		for m: Dictionary in h.capture.messages:
			var t: int = int(Variants.number(m["type"]))
			if t == Protocol.Msg.SAVE_DATA or t == Protocol.Msg.JOURNAL:
				save_msgs += 1
		assert_eq(save_msgs, 0, "%s was sent no save data or journal entry" % h.name)
		assert_true(h.connection.saves.runs.is_empty() and h.connection.saves.journal_entries.is_empty())
