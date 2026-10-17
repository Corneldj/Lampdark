extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-06 with NET-07 (Gameplay §11.10, GDD §15.7): the run record serves the true view only during
## Lamp Check, and is discarded when Lamp Check ends: after it, every replay or clip request (the
## true view, a victim's view, a delayed view) returns nothing.

const W = preload("res://tests/scenario/rescue/lamp_check_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


func _ada_window(s: Scenario, ada: MinerHandle) -> RecordWindow:
	for w: RecordWindow in s.run.record.windows:
		if w.kind == RecordWindow.Kind.FALL and w.entity == ada.entity_id:
			return w
	return null


func test_the_record_serves_only_during_lamp_check_then_goes() -> void:
	var s: Scenario = make({"seed": 12201, "fixture": W.K.E.T.C.scenario_fixture()})
	var r: Array = W.first_shift(s)
	var ada: MinerHandle = r[1]
	var crew: Array[MinerHandle] = []
	crew.assign(Variants.array(r[0]))
	var window: RecordWindow = _ada_window(s, ada)
	assert_true(window != null, "Ada's fall has its window")
	if window == null:
		return
	assert_true(window.sealed)
	assert_eq(s.run.phase, RunState.Phase.LAMP_CHECK)
	assert_false(RecordReaders.true_view(s.run.record, window).is_empty(), "the true view, during Lamp Check")
	assert_false(RecordReaders.victim_view(s.run.record, window).is_empty(), "her own view, for the replay")
	for h: MinerHandle in crew + [ada]:
		W.press_ready(h)
	s.step(3)
	assert_eq(s.run.phase, RunState.Phase.ENDED)
	assert_true(s.run.record.discarded)
	assert_true(RecordReaders.true_view(s.run.record, window).is_empty(), "no true view after it")
	assert_true(RecordReaders.victim_view(s.run.record, window).is_empty(), "no replay after it")
	assert_true(RecordReaders.delayed_view(s.run.record, crew[0].slot, 1.0).is_empty(), "no clip after it")
