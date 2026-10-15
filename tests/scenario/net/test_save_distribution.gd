extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09: every member keeps the run's saves. A fall's journal entry reaches each member's PC within
## one round trip of its tick, on the control lane; each snapshot's changed sections follow on bulk,
## the member's copy assembled from them is the host's file byte for byte, and each member's
## acknowledgement reaches the server (MOD-05 reads it). The member stores what it is sent and
## opens nothing.

const S = preload("res://tests/scenario/net/save_world.gd")

const RTT_MS: int = 160


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_journal_entry_reaches_every_member_within_one_round_trip() -> void:
	S.clear(911)
	var s: Scenario = make(S.cfg(911))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	var cat: MinerHandle = S.miner(s, "cat", Vector2i(10, 4))
	bob.link(RTT_MS, 0.0)
	cat.link(RTT_MS, 0.0)
	s.step(10)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	var tick_ms: float = 1000.0 / Tuning.f(&"net.tick_hz")
	var held: Dictionary = {}
	for _i: int in 40:
		s.step(1)
		for h: MinerHandle in [bob, cat]:
			if not held.has(h.name) and not h.connection.saves.journal_entries.is_empty():
				held[h.name] = s.run.tick
		if held.size() == 2:
			break
	assert_eq(s.run.saves.journal.entries.size(), 1)
	var fall_tick: int = int(Variants.number(s.run.saves.journal.entries[0]["tick"]))
	for h: MinerHandle in [bob, cat]:
		assert_true(held.has(h.name), "%s holds the entry" % h.name)
		var after_ms: float = (int(Variants.number(held.get(h.name, 9999))) - fall_tick) * tick_ms
		gut.p("%s held the entry %.0f ms after the fall tick (RTT %d ms)" % [h.name, after_ms, RTT_MS])
		assert_lte(after_ms, RTT_MS + tick_ms, "within one round trip (to the tick)")
		var on_disk: String = h.connection.saves.root.path_join(s.run.header.run_uuid).path_join(SaveStore.JOURNAL_FILE)
		assert_true(FileAccess.file_exists(on_disk), "on the member's disk")


func test_every_member_holds_the_hosts_save_and_acknowledges_it() -> void:
	S.clear(912)
	var s: Scenario = make(S.cfg(912))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	S.L.lit_in_hand(s, ann)
	for n: int in [1, 2]:
		assert_true(S.until_saved(s, n), "snapshot %d" % n)
		s.step(10)
		s.run.saves.flush()
		var host: PackedByteArray = FileAccess.get_file_as_bytes(S.snapshot_path(s))
		for h: MinerHandle in [ann, bob]:
			var copy: PackedByteArray = FileAccess.get_file_as_bytes(h.connection.saves.path_of(s.run.header.run_uuid))
			assert_eq(copy.size(), host.size(), "%s's copy of save %d: the same size" % [h.name, n])
			assert_true(copy == host, "%s's copy of save %d: the host's file byte for byte" % [h.name, n])
			assert_eq(int(Variants.number(s.run.saves.acks.get(h.slot, -1))), n, "%s acknowledged save %d" % [h.name, n])
	# The second carried only the sections that changed.
	var sent: Array[int] = []
	for m: Dictionary in bob.capture.messages:
		if int(Variants.number(m["type"])) == Protocol.Msg.SAVE_DATA:
			var bytes: PackedByteArray = m["bytes"]
			var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
			var d: Dictionary = SaveWire.read_save_data(payload)
			sent.append(Variants.dict(d["changed"]).size())
	gut.p("sections sent per save: %s" % str(sent))
	assert_eq(sent.size(), 2)
	assert_lt(sent[1], sent[0], "the second save sent only what changed")


func test_a_member_joining_late_is_sent_the_whole_save() -> void:
	S.clear(913)
	var s: Scenario = make(S.cfg(913))
	S.miner(s, "ann", Vector2i(3, 3))
	assert_true(S.until_saved(s, 1))
	var cat: MinerHandle = S.miner(s, "cat", Vector2i(10, 4))
	assert_true(S.until_saved(s, 2))
	s.step(10)
	s.run.saves.flush()
	var host: PackedByteArray = FileAccess.get_file_as_bytes(S.snapshot_path(s))
	var copy: PackedByteArray = FileAccess.get_file_as_bytes(cat.connection.saves.path_of(s.run.header.run_uuid))
	assert_true(not copy.is_empty() and copy == host, "her first save is whole: the host's file")
	assert_eq(int(Variants.number(s.run.saves.acks.get(cat.slot, -1))), 2)
