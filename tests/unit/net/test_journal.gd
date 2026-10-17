extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09's journal: every fall and death is written the tick it happens, to the disk at once and
## hash-chained; a resume takes the run's entries whose seal and chain hold, and applies only
## those after its snapshot's tick, each once.

const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _crew(run_seed: int) -> Array:
	S.clear(run_seed)
	var s: Scenario = make(S.cfg(run_seed))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	var cat: MinerHandle = S.miner(s, "cat", Vector2i(10, 4))
	# Dan stays up: with the whole crew down the run is wiped (LFT-11) and its journal closes.
	S.miner(s, "dan", Vector2i(12, 1))
	s.step(5)
	return [s, ann, bob, cat]


func test_entries_are_written_the_tick_they_happen_and_chained() -> void:
	var w: Array = _crew(951)
	var s: Scenario = w[0]
	var path: String = s.run.saves.run_dir().path_join(Saves.JOURNAL_FILE)
	var ticks: Array[int] = []
	for i: int in 3:
		var h: MinerHandle = w[i + 1]
		if i == 2:
			s.run.miner_state.kill(h.entity_id, "kit")
		else:
			assert_true(s.run.falls.fall_unconscious(s.run, h.entity_id, FallCause.Cause.ROOF_FALL))
		s.step(1)
		var state_tick: int = s.run.tick - 1
		assert_eq(s.run.saves.journal.entries.size(), i + 1, "written the tick it happened")
		var on_disk: Array[Dictionary] = Saves.read_journal(path)
		assert_eq(on_disk.size(), i + 1, "on the disk at once, no flush")
		ticks.append(int(Variants.number(on_disk[i]["tick"])))
		assert_lte(absi(ticks[i] - state_tick), 1)
		s.step(4)
	var entries: Array[Dictionary] = s.run.saves.journal.entries
	assert_true(Journal.chain_holds(entries), "hash-chained")
	assert_eq(str(entries[2]["kind"]), "death")
	var keys: Array = entries[0].keys()
	keys.sort()
	assert_eq(keys, ["after_snapshot_seq", "body_tile", "cause", "hash", "kind", "lamp_end", "marks", "miner", "prev", "run_uuid", "tick"])
	var broken: Array[Dictionary] = []
	for e: Dictionary in entries:
		broken.append(e.duplicate(true))
	broken[1]["body_tile"] = Vector2i(1, 1)
	assert_false(Journal.chain_holds(broken), "a changed entry breaks the chain")


func test_a_resume_reads_only_what_holds() -> void:
	var w: Array = _crew(952)
	var s: Scenario = w[0]
	for i: int in 3:
		var h: MinerHandle = w[i + 1]
		assert_true(s.run.falls.fall_unconscious(s.run, h.entity_id, FallCause.Cause.ROOF_FALL))
		s.step(3)
	var entries: Array[Dictionary] = s.run.saves.journal.entries
	var path: String = "user://net09_unit/journal/journal.bin"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# Another run's entry, the first two, the second changed and resealed (its seal holds, its
	# hash does not), the third: a resume reads up to the break.
	var other: Dictionary = entries[0].duplicate(true)
	other["run_uuid"] = "someone else"
	var changed: Dictionary = entries[1].duplicate(true)
	changed["cause"] = "nothing"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	for e: Dictionary in [other, entries[0], changed, entries[2]]:
		var sealed: PackedByteArray = LbSeal.seal(var_to_bytes(e))
		f.store_32(sealed.size())
		f.store_buffer(sealed)
	f.store_32(9999)  # a write cut short
	f.close()
	var got: Array[Dictionary] = SaveResume.read_journal(path, s.run.header.run_uuid)
	assert_eq(got.size(), 1, "the run's entries up to the break")
	assert_eq(got[0], entries[0])


func test_only_entries_after_the_snapshot_apply_each_once() -> void:
	var w: Array = _crew(953)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(3)
	var mid: int = s.run.tick
	s.step(3)
	s.run.miner_state.kill(bob.entity_id, "kit")
	s.step(3)
	var entries: Array[Dictionary] = s.run.saves.journal.entries
	assert_eq(entries.size(), 2)
	var b: Scenario = make(S.cfg(953))
	var ann2: MinerHandle = S.miner(b, "ann", Vector2i(3, 3))
	var bob2: MinerHandle = S.miner(b, "bob", Vector2i(8, 3))
	assert_eq(Journal.apply_after(b.run, entries, mid), 1, "only the death after the snapshot tick")
	assert_eq(b.run.miner_state.life(bob2.entity_id), MinerTransitions.Life.DEAD)
	assert_eq(b.run.miner_state.life(ann2.entity_id), MinerTransitions.Life.UPRIGHT, "the earlier fall is the snapshot's")
	assert_eq(Journal.apply_after(b.run, entries, s.run.tick), 0, "nothing after the newest snapshot")


func test_a_public_run_journals_nothing() -> void:
	S.clear(954)
	var s: Scenario = make(S.cfg(954, ServerConfig.Mode.PUBLIC))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	s.step(3)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(3)
	assert_eq(s.run.saves.journal.entries.size(), 0)
	assert_eq(s.run.saves.journal.write(s.run, ann.entity_id, "fall", "kit"), {})
	assert_false(FileAccess.file_exists(s.run.saves.run_dir().path_join(Saves.JOURNAL_FILE)))
