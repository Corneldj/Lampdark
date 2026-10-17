extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 with NET-09 (Gameplay §3.8, GDD §15.10): a run that has ended never resumes. Its end, here
## a crew of three wiped (no lone-human self-revive: that is a crew of two's), is the journal's last
## entry, after the last fall, and names no outcome; it reaches every member's copy with the host's,
## SaveResume refuses any copy, and no snapshot or abnormal end follows.

const S = preload("res://tests/scenario/net/save_world.gd")

const SEED: int = 11701


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_all() -> void:
	S.clear(SEED)


func test_a_wiped_run_never_resumes() -> void:
	S.clear(SEED)
	var s: Scenario = make(S.cfg(SEED))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	var cat: MinerHandle = S.miner(s, "cat", Vector2i(10, 4))
	assert_true(S.until_saved(s, 1), "a snapshot to resume from")
	var path: String = S.snapshot_path(s)
	assert_true(Variants.flag(SaveResume.open_file(path)["ok"]), "under way, it resumes")
	for h: MinerHandle in [ann, cat]:
		assert_true(s.run.falls.fall_unconscious(s.run, h.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(3)
	assert_false(s.run.outcomes.ended, "Bob stands")
	assert_false(s.run.self_revive.deferral_active(), "a crew of three: no lone-human self-revive")
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.ROOF_FALL))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.outcomes.ended, 5), "the wipe")
	s.step(5)
	s.run.saves.flush()
	var entries: Array[Dictionary] = s.run.saves.journal.entries
	assert_gte(entries.size(), 4)
	var last: Dictionary = entries[entries.size() - 1]
	assert_eq(str(last["kind"]), Journal.KIND_ENDED, "the end is the last entry")
	assert_eq(str(last["cause"]), "wipe")
	assert_eq(str(entries[entries.size() - 2]["kind"]), "fall", "after Bob's fall")
	assert_eq(int(Variants.number(entries[entries.size() - 2]["miner"])), bob.entity_id)
	for key: String in ["outcome", "outcomes", "up_count", "miners", "wipe"]:
		assert_false(last.has(key), "it names no outcome (%s)" % key)
	var refused: Dictionary = SaveResume.open_file(path)
	assert_false(Variants.flag(refused["ok"]))
	assert_eq(str(refused["error"]), SaveResume.ERR_ENDED, "the host's copy is refused")
	for h: MinerHandle in [ann, bob, cat]:
		var copy: Dictionary = SaveResume.open_file(h.connection.saves.path_of(s.run.header.run_uuid))
		assert_eq(str(copy["error"]), SaveResume.ERR_ENDED, "%s's copy is refused" % h.name)
	var written: int = s.run.saves.written.size()
	s.step(roundi((Tuning.f(&"net.snapshot_interval_s") + 2.0) * Tuning.f(&"net.tick_hz")))
	assert_eq(s.run.saves.written.size(), written, "no snapshot after the end")
	assert_true(s.run.saves.end_abnormally(s.run, "the host quit").is_empty(), "nor an abnormal end's")
