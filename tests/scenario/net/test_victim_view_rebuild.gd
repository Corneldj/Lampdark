extends "res://tests/scenario/kit/scenario_test.gd"
## NET-07: for a scripted fall, victim_view() rebuilds the victim's client view frame for frame from
## the frames that client acknowledged, illusions included and marked, compared with what the
## client itself decoded. The victim's link loses frames, so the rebuild must follow the acks.

const W = preload("res://tests/scenario/net/record_world.gd")
const FALL_AT: int = 420
const ILLUSION_AT: int = 340


## A stand-in for CRT-10's illusion stage: one rock tap that never was, for one client, logged.
class IllusionStub:
	extends SimSystem
	var slot: int = 0
	var entity: int = 0
	var at_tick: int = 0

	func stage() -> int:
		return StageTable.Stage.ILLUSIONS

	func order() -> int:
		return 0

	func system_name() -> String:
		return "illusion_stub"

	func tick(run: RunState) -> void:
		if run.tick != at_tick:
			return
		var r: AudioRecord = AudioRecord.new()
		r.type = NoiseTypes.Type.ROCK_TAP
		r.start_tick = run.tick
		r.apparent = run.registry.get_entity(entity).position + Vector2(3.0, 0.0)
		r.remaining_np = 2.0
		r.level_np = 4.0
		r.duration_s = 0.5
		run.replication.append_illusion_event(slot, r.to_event(), 77)
		run.record.lie_log_append({"tick": run.tick, "slot": slot, "illusion_id": 77, "type": "rock_tap"})


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_victim_view_matches_the_client_frame_for_frame() -> void:
	var stub: IllusionStub = IllusionStub.new()
	var s: Scenario = make({"seed": 71, "fixture": "test", "systems": [stub]})
	var miners: Array[MinerHandle] = W.crew(s, 2, 71, [120, 3.0])
	var ann: MinerHandle = miners[0]
	stub.slot = ann.slot
	stub.entity = ann.entity_id
	stub.at_tick = ILLUSION_AT
	var client: Dictionary = W.decoded_by_tick(s, ann)
	s.step(FALL_AT - s.run.tick)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(220)
	var w: RecordWindow = W.window_of(s, RecordWindow.Kind.FALL, ann.entity_id)
	assert_not_null(w, "the fall pinned a window")
	if w == null:
		return
	assert_true(w.sealed, "the window copied its blocks out of the ring")
	assert_eq(w.slot, ann.slot)
	var hz: float = Tuning.f(&"net.tick_hz")
	assert_eq(w.start, w.cause_tick - roundi(Tuning.f(&"net.record_event_window_s") * hz), "15 s before the cause")
	assert_eq(w.cause_tick, FALL_AT, "a smothering's cause is the fall itself")
	assert_eq(w.end, FALL_AT + roundi(Tuning.f(&"net.record_tail_s") * hz), "the tail after the fall")
	var rebuilt: Array[Dictionary] = RecordReaders.victim_view(s.run.record, w)
	var expected: Array[int] = []
	for raw: Variant in client.keys():
		var t: int = raw
		if t >= w.start and t <= w.end:
			expected.append(t)
	expected.sort()
	var got: Array[int] = []
	var mismatched: Array[int] = []
	var marked: Array[Dictionary] = []
	for entry: Dictionary in rebuilt:
		var t: int = entry["tick"]
		got.append(t)
		var mine: Array = Variants.array(client.get(t, []))
		var view: ReceivedView = entry["view"]
		var theirs: ReceivedView = mine[0] if not mine.is_empty() else null
		if theirs == null or not view.same_as(theirs) or Variants.array(entry["events"]) != Variants.array(mine[1]):
			mismatched.append(t)
		var numbers: PackedInt32Array = entry["illusions"]
		for n: int in numbers:
			for e: Dictionary in Variants.array(entry["events"]):
				if int(Variants.number(e["number"])) == n:
					marked.append(e)
	gut.p("window %d-%d: %d frames rebuilt, %d decoded by the client; record lost-frame acks late: %d; keyframe misses: %d" % [
		w.start, w.end, got.size(), expected.size(), s.run.record.late_acks, s.run.record.keyframe_misses])
	assert_lt(expected.size(), w.end - w.start + 1, "the link lost some of the window's frames")
	assert_eq(got, expected, "exactly the frames the client decoded")
	assert_eq(mismatched, [] as Array[int], "every rebuilt view and its events match the client's")
	assert_eq(s.run.record.keyframe_misses, 0)
	assert_eq(marked.size(), 1, "the illusion is in the rebuilt stream, marked as a lie")
	if marked.size() == 1:
		assert_eq(int(Variants.number(marked[0]["start_tick"])), ILLUSION_AT)
	var lies: Array[Dictionary] = RecordReaders.window_lies(s.run.record, w)
	assert_eq(lies.size(), 1, "the window carries the victim's lie-log entry")
	var first: RecordWindow = W.window_of(s, RecordWindow.Kind.FIRST_ILLUSION, ann.entity_id)
	assert_not_null(first, "the miner's first illusion pinned its own window")
	if first != null:
		assert_eq(first.cause_tick, ILLUSION_AT)


func test_frames_carry_arrival_estimates() -> void:
	var s: Scenario = make({"seed": 72, "fixture": "test"})
	var miners: Array[MinerHandle] = W.crew(s, 1, 72, [200, 0.0])
	s.step(200)
	assert_true(s.run.falls.fall_unconscious(s.run, miners[0].entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(200)
	var w: RecordWindow = W.window_of(s, RecordWindow.Kind.FALL, miners[0].entity_id)
	var rebuilt: Array[Dictionary] = RecordReaders.victim_view(s.run.record, w)
	assert_gt(rebuilt.size(), 100)
	var total: int = 0
	for entry: Dictionary in rebuilt:
		total += int(Variants.number(entry["arrival_ms"]))
	var mean: float = float(total) / rebuilt.size()
	gut.p("mean estimated arrival at 200 ms RTT: %.1f ms" % mean)
	assert_between(mean, 60.0, 160.0, "about half the RTT, from the acks' receive delays")
