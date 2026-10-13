extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-05 through real inputs: ann picks share oil and holds; bob holds with her, then lets go
## halfway: the share cancels, nothing changes, and it was bob who let go. Holding together, it
## completes and both founts level.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_cancel_then_complete() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	var la: GauzeLamp = L.lit_in_hand(s, ann)
	var lb: GauzeLamp = L.lit_in_hand(s, bob)
	la.oil = 0.9
	lb.oil = 0.1
	var ends: Array = []
	R.tap(s, ann)
	var options: Array = Variants.array(ann.connection.ring.get("options", []))
	ann.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, options.find("share_oil"))
	s.step(3)
	s.on_tick = func(sc: Scenario) -> void:
		var act: TimedAction = sc.run.inventory.actions.get(ann.entity_id, null)
		if act != null and not act.cancelled.is_connected(_noop):
			act.cancelled.connect(func(x: TimedAction, why: StringName) -> void: ends.append([str(why), x.let_go]))
			act.cancelled.connect(_noop)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(90)
	assert_eq(ends, [["partner", bob.entity_id]], "bob let go")
	assert_gt(la.oil, 0.85, "nothing shared")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 75)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 75)
	s.step(85)
	assert_almost_eq(la.oil, lb.oil, 1e-12, "held together, it completes")


func _noop(_x: TimedAction, _why: StringName) -> void:
	pass
