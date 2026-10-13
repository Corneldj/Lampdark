extends "res://tests/scenario/kit/scenario_test.gd"
## FND-09: withhold_inputs(5) (250 ms) trips NET-03's 200 ms rule: the miner stops and its timed
## action is cancelled, nothing spent. link(120, 0) delivers inputs 60 ms late, stamped with the
## tick the client was showing.

const Sample = preload("res://tests/scenario/kit/sample.gd")


## A stand-in for MNR-04's timed action: holding interact runs a 3 s action that spends its
## oil only on completion; input_starved cancels it with nothing spent.
class TimedActionStub:
	extends SimSystem
	var slot: int = 0
	var progress: int = -1
	var spent: int = 0
	var cancelled_at: int = -1
	var starved_events: int = 0

	func stage() -> int:
		return StageTable.Stage.MINERS

	func order() -> int:
		return 91

	func system_name() -> String:
		return "timed_action_stub"

	func tick(run: RunState) -> void:
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			return
		if progress < 0 and (c.record.holds & InputRecord.HOLD_INTERACT) != 0:
			progress = 0
		elif progress >= 0:
			progress += 1
			if progress >= 60:
				spent += 1
				progress = -1

	func on_starved(starved_slot: int, at_tick: int) -> void:
		if starved_slot != slot:
			return
		starved_events += 1
		if progress >= 0:
			progress = -1
			cancelled_at = at_tick


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_withholding_250_ms_stops_the_miner_and_cancels_the_action() -> void:
	var stub: TimedActionStub = TimedActionStub.new()
	var s: Scenario = make({"seed": 4, "fixture": Sample.fixture(), "systems": [stub]})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	stub.slot = ann.slot
	s.run.inputs.input_starved.connect(func(slot: int) -> void: stub.on_starved(slot, s.run.tick))
	ann.at(0).hold(InputRecord.HOLD_INTERACT, 400)
	ann.inputs.at(0).move(0.0, InputRecord.Gait.WALK, 400)
	s.step(20)
	assert_gt(stub.progress, 10, "the action is under way")
	ann.withhold_inputs(5)
	var stopped_at: Array[int] = [-1]
	s.on_tick = func(scenario: Scenario) -> void:
		var view: Dictionary = scenario.state.miner(ann)
		if Variants.flag(view["starved"]) and stopped_at[0] < 0:
			stopped_at[0] = scenario.run.tick - 1
			var record: InputRecord = view["input"]
			assert_eq(record.move_dir, InputRecord.NO_DIRECTION, "movement zeroed")
			assert_eq(record.holds, 0, "controls released")
	s.step(10)
	assert_gt(stopped_at[0], 0, "the 200 ms rule stopped the miner")
	assert_eq(stub.cancelled_at, stopped_at[0], "the action was cancelled on the stop")
	assert_eq(stub.spent, 0, "nothing spent")
	assert_eq(stub.starved_events, 1)
	assert_eq(s.run.inputs.buffer_for(ann.slot).starved_count, 1)
	# The capture shows it: Ann's own block goes still on the stop.
	var before: ReceivedView = s.client(ann).records_at(stopped_at[0] - 1)
	var at_stop: ReceivedView = s.client(ann).records_at(stopped_at[0] + 1)
	assert_ne(int(Variants.number(before.own["gait"])), 255, "walking before the cut-off")
	assert_eq(int(Variants.number(at_stop.own["gait"])), 255, "still once stopped")
	var moved: Vector2 = at_stop.own["position"] - before.own["position"]
	assert_lt(moved.length(), 0.2, "no more than the last repeated step")


func test_withholding_four_ticks_is_only_a_repeat() -> void:
	var stub: TimedActionStub = TimedActionStub.new()
	var s: Scenario = make({"seed": 5, "systems": [stub]})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(1, 1))
	stub.slot = ann.slot
	s.run.inputs.input_starved.connect(func(slot: int) -> void: stub.on_starved(slot, s.run.tick))
	ann.at(0).hold(InputRecord.HOLD_INTERACT, 400)
	s.step(10)
	ann.withhold_inputs(4)
	s.step(20)
	assert_eq(stub.starved_events, 0, "four missing inputs (200 ms) only repeat")
	assert_eq(s.run.inputs.buffer_for(ann.slot).gaps, 1, "one gap of repeats")


func test_link_delivers_inputs_half_the_rtt_late() -> void:
	var s: Scenario = make({"seed": 6})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(1, 1))
	ann.link(120, 0.0)
	ann.at(0).move(90.0, InputRecord.Gait.WALK, 40)
	s.step(40)
	var delays: Dictionary = {}
	for seq: Variant in ann.link_filter.input_delivered_usec.keys():
		var sent: int = int(Variants.number(ann.link_filter.input_sent_usec[seq]))
		var delivered: int = int(Variants.number(ann.link_filter.input_delivered_usec[seq]))
		delays[delivered - sent] = true
	assert_eq(delays.keys(), [60000], "every input arrives 60 ms after it was sent")
	# Every packet the server received carries the tick the client was showing when it sent it.
	var shown_by_seq: Dictionary = {}
	for stamp: PackedInt64Array in ann.sent_stamps:
		shown_by_seq[stamp[0]] = stamp[1]
	var checked: int = 0
	for m: Dictionary in s.server_capture.messages:
		if int(Variants.number(m["type"])) != Protocol.Msg.INPUT:
			continue
		var bytes: PackedByteArray = m["bytes"]
		var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
		var packet: InputPacket = InputPacket.decode(payload)
		assert_eq(packet.shown_tick, int(Variants.number(shown_by_seq[packet.newest_seq])))
		checked += 1
	assert_gt(checked, 30)
	var newest_frame_seen: int = ann.connection.last_frame_tick
	assert_lt(newest_frame_seen, s.run.tick - 1, "with 60 ms each way the client is showing an older tick")
