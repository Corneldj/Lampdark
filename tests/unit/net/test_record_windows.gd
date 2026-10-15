extends "res://tests/scenario/kit/scenario_test.gd"
## NET-07's pinned windows: one round each fall and each death, a drag's from its grab; RSC-07's
## facts taken at the pin; the window outlives the ring's roll (shortened here) and reaches NET-09
## intact; and over the budget, the oldest windows' keyframes thin to every 4 s and still replay.

const W = preload("res://tests/scenario/net/record_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _views(s: Scenario, w: RecordWindow) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in RecordReaders.victim_view(s.run.record, w):
		var view: ReceivedView = entry["view"]
		out.append({"tick": entry["tick"], "view": view.to_dict(), "events": entry["events"]})
	return out


func test_a_window_survives_the_roll_and_reaches_netnine_intact() -> void:
	var s: Scenario = make({"seed": 91, "fixture": "test", "overrides": {"net.record_window_s": 20.0}})
	var miners: Array[MinerHandle] = W.crew(s, 2, 91)
	var ann: MinerHandle = miners[0]
	s.run.record.fact_extractor = func(run: RunState, w: RecordWindow) -> Dictionary:
		return {"warning": "stub", "tick": run.tick, "kind": RecordWindow.kind_name(w.kind)}
	s.step(300)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(200)
	var w: RecordWindow = W.window_of(s, RecordWindow.Kind.FALL, ann.entity_id)
	assert_not_null(w)
	if w == null:
		return
	assert_true(w.sealed)
	assert_eq(w.facts, {"warning": "stub", "tick": 300, "kind": "fall"}, "RSC-07's facts are taken at the pin")
	var before: Array[Dictionary] = _views(s, w)
	assert_gt(before.size(), 300)
	s.step(800)  # 40 s: the ring (20 s here) has rolled past the whole window
	assert_gt(s.run.record.ring[0].start, w.end, "the ring no longer holds any of the window")
	assert_eq(_views(s, w), before, "the window still replays exactly")
	var saved: Array = s.run.record.export_windows()
	assert_eq(saved.size(), 1)
	var bytes: PackedByteArray = var_to_bytes(saved)
	var other: Scenario = make({"seed": 92, "fixture": "test"})
	var loaded: Array = bytes_to_var(bytes)
	other.run.record.import_windows(loaded)
	var back: RecordWindow = other.run.record.windows[0]
	assert_eq(back.to_dict(), w.to_dict(), "every field and byte survives the save")
	assert_eq(_views(other, back), before, "and replays the same frames in another session")


func test_a_drag_window_starts_at_the_grab_and_a_death_pins_one() -> void:
	var s: Scenario = make({"seed": 93, "fixture": "test"})
	var miners: Array[MinerHandle] = W.crew(s, 2, 93)
	s.step(400)
	s.run.holds.grab_begun.emit(9, GrabHold.Kind.STYTHE_DRAG, 0, miners[0].entity_id)  # the grab, at tick 400
	s.step(300)
	assert_true(s.run.falls.fall_unconscious(s.run, miners[0].entity_id, FallCause.Cause.DRAG, {"grab_id": 9}))
	s.run.miner_state.kill(miners[1].entity_id, "test")
	s.step(150)
	var hz: float = Tuning.f(&"net.tick_hz")
	var drag: RecordWindow = W.window_of(s, RecordWindow.Kind.FALL, miners[0].entity_id)
	assert_not_null(drag)
	if drag != null:
		assert_eq(drag.cause_tick, 400, "a drag's cause is the grab")
		assert_eq(drag.start, 400 - roundi(Tuning.f(&"net.record_event_window_s") * hz))
		assert_eq(drag.end, 700 + roundi(Tuning.f(&"net.record_tail_s") * hz), "through the fall and its tail")
		assert_true(drag.sealed)
	var death: RecordWindow = W.window_of(s, RecordWindow.Kind.DEATH, miners[1].entity_id)
	assert_not_null(death, "a death pins a window")
	if death != null:
		assert_eq(death.cause_tick, 700)
		assert_eq(death.slot, miners[1].slot)


func test_over_budget_the_oldest_windows_thin_and_still_replay() -> void:
	var s: Scenario = make({"seed": 94, "fixture": "test"})
	var miners: Array[MinerHandle] = W.crew(s, 3, 94)
	s.step(340)
	for h: MinerHandle in miners:
		assert_true(s.run.falls.fall_unconscious(s.run, h.entity_id, FallCause.Cause.MOTH_SMOTHER))
		s.step(60)
	s.step(150)
	var r: RunRecord = s.run.record
	assert_eq(r.windows.size(), 3)
	var before: Array = []
	for w: RecordWindow in r.windows:
		assert_true(w.sealed)
		before.append(_views(s, w))
	var windows_before: int = r.windows_bytes()
	r.budget_bytes = r.memory_bytes() - 1  # just over: the oldest window thins, the rest stay
	r._enforce_budget()
	assert_true(r.windows[0].thinned, "the oldest window thinned")
	assert_false(r.windows[2].thinned, "the newest did not need to")
	assert_eq(r.windows.size(), 3, "no window is ever dropped")
	assert_lt(r.windows_bytes(), windows_before)
	var counted: int = 0
	for w: RecordWindow in r.windows:
		counted += w.size()
	assert_eq(r.windows_bytes(), counted, "the running count follows the thinning")
	assert_eq(r.thinning_log.size(), 1)
	gut.p(r.thinning_log[0])
	for i: int in r.windows.size():
		var w: RecordWindow = r.windows[i]
		var kept: int = 0
		for b: RecordBlock in w.blocks:
			kept += 1 if b.has_keyframes() else 0
		if w.thinned:
			assert_eq(kept, ceili(w.blocks.size() / 2.0), "a keyframe every 4 s")
		var was: Array = before[i]
		assert_eq(_views(s, w), was, "window %d replays exactly" % w.id)
