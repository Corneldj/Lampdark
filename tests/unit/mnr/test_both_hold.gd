extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-05: a both-hold completes only when every participant holds for the full time; a release by
## either at any tick, or a partner leaving touch range, cancels it with nothing changed and says who
## let go.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")

var _holds: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


## A share of oil started by ann with bob; `release_at`: {who: tick into the action}.
func _share(run_seed: int, release_at: Dictionary) -> Array:
	_holds = {}
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	var la: GauzeLamp = L.lit_in_hand(s, ann)
	var lb: GauzeLamp = L.lit_in_hand(s, bob)
	la.oil = 0.9
	lb.oil = 0.1
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return int(Variants.number(_holds.get(slot, 0)))
	var a: TimedAction = BothHold.join(LampOil.share_action(s.run, ann.entity_id, bob.entity_id), [bob.entity_id] as Array[int])
	var ends: Array = []
	a.completed.connect(func(_x: TimedAction) -> void: ends.append("completed"))
	a.cancelled.connect(func(x: TimedAction, why: StringName) -> void: ends.append([str(why), x.let_go]))
	assert_true(s.run.inventory.start_action(s.run, a))
	_holds[ann.slot] = InputRecord.HOLD_INTERACT
	_holds[bob.slot] = InputRecord.HOLD_INTERACT
	for k: int in 65:
		for who: Variant in release_at.keys():
			if int(Variants.number(release_at[who])) == k:
				_holds[(ann if str(who) == "ann" else bob).slot] = 0
		s.step(1)
	return [ends, la, lb, ann, bob]


func test_full_hold_completes() -> void:
	var r: Array = _share(1, {})
	assert_eq(Variants.array(r[0]), ["completed"])
	var la: GauzeLamp = r[1]
	var lb: GauzeLamp = r[2]
	assert_almost_eq(la.oil, lb.oil, 1e-12)


func test_any_release_cancels() -> void:
	var cases: Array = [{"bob": 0}, {"bob": 30}, {"bob": 58}, {"ann": 15}, {"ann": 59}]
	for i: int in cases.size():
		var r: Array = _share(10 + i, Variants.dict(cases[i]))
		var ends: Array = r[0]
		var la: GauzeLamp = r[1]
		var lb: GauzeLamp = r[2]
		var bob: MinerHandle = r[4]
		assert_eq(ends.size(), 1, "case %s" % [cases[i]])
		assert_ne(str(ends[0]), "completed", "%s: cancelled" % [cases[i]])
		assert_gt(la.oil, 0.85, "%s: nothing shared" % [cases[i]])
		assert_lt(lb.oil, 0.15)
		if Variants.dict(cases[i]).has("bob"):
			assert_eq(Variants.array(ends[0]), ["partner", bob.entity_id], "who let go")


func test_partner_out_of_reach_cancels() -> void:
	_holds = {}
	var s: Scenario = make({"seed": 20, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	L.lit_in_hand(s, ann)
	L.lit_in_hand(s, bob)
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return InputRecord.HOLD_INTERACT if slot in [ann.slot, bob.slot] else 0
	var a: TimedAction = BothHold.join(Relight.pass_flame_action(s.run, ann.entity_id, bob.entity_id), [bob.entity_id] as Array[int])
	var ends: Array[StringName] = []
	a.cancelled.connect(func(_x: TimedAction, why: StringName) -> void: ends.append(why))
	s.run.lamps.snuff(s.run, s.run.lamps.lamp_in_hand(bob.entity_id), "test")
	assert_true(s.run.inventory.start_action(s.run, a))
	s.step(10)
	var far: Vector2 = s.run.registry.get_entity(bob.entity_id).position + Vector2(2.5, 0)
	s.run.registry.move(bob.entity_id, far)
	s.run.movement.miner(bob.slot).state.x = far.x
	s.step(5)
	assert_eq(ends, [TimedAction.PARTNER] as Array[StringName], "he left touch range")
