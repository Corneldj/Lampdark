extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-04: shared work for two (Gameplay §3.3). 10 s with two miners holding both places, 20 s alone
## (lift.alone_work_multiplier); in a crew that is not alone one miner holding makes no progress, and
## what was done is kept when a place is let go (Proposed). Nothing of it reaches a client: the
## clients hear only the job's own events, and their status says only that they stand at a job.

const J = preload("res://tests/unit/lift/job_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _ticks_to_complete(s: Scenario, events: Array, limit: int) -> int:
	var start: int = s.run.tick
	for i: int in limit:
		s.step(1)
		if not events.is_empty():
			return int(Variants.number(Variants.array(events[0])[1])) - start
	return -1


func test_two_miners_take_ten_seconds() -> void:
	var s: Scenario = make({"seed": 2001, "fixture": J.room()})
	var events: Array = []
	var job: PairedWork = J.paired_work(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.A_TILE, Vector2i(0, 1))
	var bob: MinerHandle = J.beside(s, "bob", J.B_TILE, Vector2i(0, 1))
	s.step(10)
	J.hold(s, ann, 400)
	J.hold(s, bob, 400)
	var took: int = _ticks_to_complete(s, events, 400)
	gut.p("two miners: %d ticks" % took)
	assert_almost_eq(took, 200, 3, "10 s")
	assert_true(job.done)


func test_alone_it_takes_twice_as_long() -> void:
	# A friends lobby of one is solo (MOD-03's solo rules).
	var s: Scenario = make({"seed": 2002, "fixture": J.room()})
	var events: Array = []
	J.paired_work(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.A_TILE, Vector2i(0, 1))
	s.step(10)
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "solo")
	J.hold(s, ann, 600)
	var took: int = _ticks_to_complete(s, events, 600)
	gut.p("alone: %d ticks" % took)
	assert_almost_eq(took, 400, 3, "20 s")


func test_in_a_crew_one_miner_makes_no_progress_and_progress_is_kept() -> void:
	var s: Scenario = make({"seed": 2003, "fixture": J.room()})
	var events: Array = []
	var job: PairedWork = J.paired_work(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.A_TILE, Vector2i(0, 1))
	var bob: MinerHandle = J.beside(s, "bob", J.B_TILE, Vector2i(0, 1))
	s.step(10)
	assert_false(AloneRules.is_alone(s.run, ann.entity_id))
	J.hold(s, ann, 100)
	s.step(100)
	assert_eq(job.progress, 0.0, "Ann alone at the gear, Bob idle: nothing")
	J.hold(s, ann, 60)
	J.hold(s, bob, 60)
	s.step(80)
	var kept: float = job.progress
	assert_gt(kept, 40.0, "together, it went on")
	s.step(100)
	assert_eq(job.progress, kept, "let go, what was done is kept")
	# Nothing but the job's own events and the 'at a job' status reached either client.
	for h: MinerHandle in [ann, bob]:
		for m: Dictionary in h.capture.messages:
			var type: int = int(Variants.number(m["type"]))
			assert_true(type in [Protocol.Msg.FRAME, Protocol.Msg.STATUS, Protocol.Msg.INVENTORY, Protocol.Msg.PONG,
				Protocol.Msg.WELCOME, Protocol.Msg.SHEET, Protocol.Msg.CLOSE_UP, Protocol.Msg.SAVE_DATA, Protocol.Msg.AMBIENT],
				"%s got a %s" % [h.name, Protocol.Msg.find_key(type)])
		var flags: Array = []
		for m: Dictionary in h.capture.messages:
			if int(Variants.number(m["type"])) == Protocol.Msg.STATUS:
				var bytes: PackedByteArray = m["bytes"]
				var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
				var st: Dictionary = StatusWire.decode(payload)
				flags.append(int(Variants.number(st.get("flags", 0))))
		assert_true(flags.has(StatusWire.AT_JOB), "%s's status said they stand at a job" % h.name)
		for f: Variant in flags:
			assert_eq(int(Variants.number(f)) & ~StatusWire.AT_JOB, 0, "and nothing else of it")
