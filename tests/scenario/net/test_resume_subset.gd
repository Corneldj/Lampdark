extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09 with MOD-05's stand-ins: a friends run resumes with only some of its crew back. The save
## holds every player's seat; whoever returns retakes theirs and their miner, a newcomer is never
## given a held seat, and the absent miners stay with Hands (MOD-05 decides who comes back and how
## an absent miner is played). A resume is complete: a resumed run captured again at once gives the
## sections it was resumed from.

const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_only_some_of_the_crew_come_back() -> void:
	S.clear(931)
	var s: Scenario = make(S.cfg(931))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	var cat: MinerHandle = S.miner(s, "cat", Vector2i(10, 4))
	assert_true(S.until_saved(s, 1))
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var b: Scenario = S.resume(make, 931, path)[0]
	# MOD-05's resume list (stand-in): the players the save holds seats for.
	var listed: Array = b.net.seats.seats.keys()
	listed.sort()
	assert_eq(listed, ["ann", "bob", "cat"], "every player's seat held")
	var back: MinerHandle = b.rejoin("ann")
	var dan: MinerHandle = b.rejoin("dan")
	b.step(3)
	assert_eq(back.entity_id, ann.entity_id, "Ann has her miner")
	assert_eq(back.slot, ann.slot, "and her seat")
	assert_eq(b.net.seats.seat_of("ann").state, SeatTable.State.SEATED)
	assert_false(b.run.hands.hands.has(ann.entity_id), "handed back to her")
	assert_true(dan.slot != bob.slot and dan.slot != cat.slot, "a newcomer never takes a held seat")
	for h: MinerHandle in [bob, cat]:
		assert_eq(b.net.seats.seat_of(h.name).state, SeatTable.State.RESERVED, "%s's seat held" % h.name)
		assert_true(b.run.hands.hands.has(h.entity_id), "a Hand keeps %s's miner" % h.name)
	b.step(100)
	assert_eq(b.run.miner_state.life(bob.entity_id), MinerTransitions.Life.UPRIGHT, "the run goes on")


func test_a_resume_is_complete() -> void:
	S.clear(932)
	var s: Scenario = make(S.cfg(932))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	S.L.lit_in_hand(s, bob)
	S.B.put(s, ItemKinds.Kind.OIL_FLASK, Vector2i(6, 5))
	s.step(20)
	# Both down before the snapshot, so the resume hands no conscious miner to a Hand.
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.DRAG, {"grab_point": Vector2i(9, 4)}))
	s.step(2)
	assert_true(S.until_saved(s, 1))
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var opened: Dictionary = SaveResume.open_file(path)
	var b: Scenario = S.resume(make, 932, path)[0]
	var again: Dictionary = Snapshot.capture(b.run, b.net)
	var was: Dictionary = opened["sections"]
	for name: String in [Snapshot.SECTION_DIFF_LOG, Snapshot.SECTION_WINDOWS]:
		var x: PackedByteArray = again.get(name, PackedByteArray())
		var y: PackedByteArray = was.get(name, PackedByteArray())
		assert_true(x == y, "%s: as saved, byte for byte" % name)
	# Every kept entity as saved; the id counter has moved on past the items the log put back.
	assert_eq(S.entities(Snapshot.section(again, Snapshot.SECTION_REGISTRY)), S.entities(Snapshot.section(was, Snapshot.SECTION_REGISTRY)),
		"the registry's entities as saved")
	var head_now: Dictionary = Snapshot.run_header(again)
	var head_was: Dictionary = Snapshot.run_header(was)
	for k: Variant in head_was.keys():
		if str(k) != "seats":
			assert_eq(var_to_str(head_now.get(k, null)), var_to_str(head_was[k]), "run header %s as saved" % str(k))
	# Seats come back held for their players (NET-11), each its slot, miner and token.
	var seats_now: Dictionary = head_now["seats"]
	var seats_was: Dictionary = head_was["seats"]
	for k: Variant in seats_was.keys():
		var now_seat: Dictionary = Variants.dict(seats_now.get(k, {}))
		var was_seat: Dictionary = seats_was[k]
		assert_eq(int(Variants.number(now_seat.get("state", -1))), SeatTable.State.RESERVED, "%s's seat held" % str(k))
		now_seat.erase("state")
		was_seat.erase("state")
		assert_eq(now_seat, was_seat, "%s's seat as saved" % str(k))
	var state_now: Dictionary = Variants.dict(bytes_to_var(Snapshot.section(again, Snapshot.SECTION_STATE)))
	var state_was: Dictionary = Variants.dict(bytes_to_var(Snapshot.section(was, Snapshot.SECTION_STATE)))
	var keys: Array = state_was.keys()
	keys.sort()
	assert_eq(state_now.keys().size(), keys.size(), "the same systems saved")
	for raw: Variant in keys:
		var a_text: String = var_to_str(state_was[raw])
		var b_text: String = var_to_str(state_now.get(raw, null))
		assert_eq(b_text, a_text, "system %s: as saved" % str(raw))
