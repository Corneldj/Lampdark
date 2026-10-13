extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-07: a flask, a can and a share each take 3 s; moving or releasing cancels with nothing spent;
## pouring tops a lamp up and the source keeps the rest; a can fills a flask; sharing leaves both
## founts at their mean; a dry lamp given oil is Out.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")

var _holds: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	_holds = {}
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(1, 0))
	s.step(1)
	var la: GauzeLamp = L.lit_in_hand(s, ann)
	var lb: GauzeLamp = L.lit_in_hand(s, bob)
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return int(Variants.number(_holds.get(slot, 0)))
	return [s, ann, bob, la, lb]


func _run_action(s: Scenario, a: TimedAction, slots: Array[int], bit: int, ticks: int) -> Array[StringName]:
	var ends: Array[StringName] = []
	a.completed.connect(func(_x: TimedAction) -> void: ends.append(&"completed"))
	a.cancelled.connect(func(_x: TimedAction, why: StringName) -> void: ends.append(why))
	assert_true(s.run.inventory.start_action(s.run, a))
	for slot: int in slots:
		_holds[slot] = bit
	s.step(ticks)
	return ends


func test_flask_tops_up_and_keeps_the_rest() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var la: GauzeLamp = parts[3]
	la.oil = 0.4
	var flask: Item = s.run.inventory.world.make(ItemKinds.Kind.OIL_FLASK, 1, {"fill": 1.0})
	var a: TimedAction = LampOil.pour_action(s.run, ann.entity_id, flask, la)
	assert_eq(a.ticks_needed, 60, "3 s")
	var ends: Array[StringName] = _run_action(s, a, [ann.slot] as Array[int], InputRecord.HOLD_USE, 62)
	assert_eq(ends, [&"completed"] as Array[StringName])
	assert_almost_eq(la.oil, 1.0, 1e-3, "topped up")
	assert_almost_eq(LampOil.oil_in(flask), 0.4, 0.01, "the flask keeps the rest")


func test_can_fills_lamp_and_flask() -> void:
	var parts: Array = _setup(2)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var la: GauzeLamp = parts[3]
	la.oil = 0.0
	s.run.lamps.mark_dry(s.run, la)
	var can: Item = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN)
	assert_eq(LampOil.oil_in(can), 4.0, "a can holds 4 fills")
	_run_action(s, LampOil.pour_action(s.run, ann.entity_id, can, la), [ann.slot] as Array[int], InputRecord.HOLD_USE, 62)
	assert_almost_eq(LampOil.oil_in(can), 3.0, 1e-9, "one fill taken: a quarter tank unit")
	assert_eq(la.state(), GauzeLamp.State.OUT, "a dry lamp given oil is Out")
	var flask: Item = s.run.inventory.world.make(ItemKinds.Kind.OIL_FLASK, 1, {"fill": 0.25})
	_holds = {}
	s.step(1)
	_run_action(s, LampOil.fill_flask_action(s.run, ann.entity_id, can, flask), [ann.slot] as Array[int], InputRecord.HOLD_USE, 62)
	assert_almost_eq(LampOil.oil_in(flask), 1.0, 1e-9)
	assert_almost_eq(LampOil.oil_in(can), 2.25, 1e-9)


func test_share_levels_to_the_mean() -> void:
	var parts: Array = _setup(3)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var la: GauzeLamp = parts[3]
	var lb: GauzeLamp = parts[4]
	la.oil = 0.9
	lb.oil = 0.1
	var ends: Array[StringName] = _run_action(s, LampOil.share_action(s.run, ann.entity_id, bob.entity_id),
		[ann.slot, bob.slot] as Array[int], InputRecord.HOLD_INTERACT, 62)
	assert_eq(ends, [&"completed"] as Array[StringName])
	assert_almost_eq(la.oil, lb.oil, 1e-12, "both founts at the mean")
	assert_almost_eq(la.oil, 0.5, 0.01, "about 0.5 (both burn as they share)")


func test_cancels_spend_nothing() -> void:
	for why: String in ["release", "move", "partner"]:
		var parts: Array = _setup(10 + why.length())
		var s: Scenario = parts[0]
		var ann: MinerHandle = parts[1]
		var bob: MinerHandle = parts[2]
		var la: GauzeLamp = parts[3]
		var lb: GauzeLamp = parts[4]
		la.oil = 0.3
		lb.oil = 0.7
		var flask: Item = s.run.inventory.world.make(ItemKinds.Kind.OIL_FLASK, 1, {"fill": 1.0})
		var a: TimedAction = LampOil.share_action(s.run, ann.entity_id, bob.entity_id) if why == "partner" \
			else LampOil.pour_action(s.run, ann.entity_id, flask, la)
		var ends: Array[StringName] = []
		a.cancelled.connect(func(_x: TimedAction, r: StringName) -> void: ends.append(r))
		assert_true(s.run.inventory.start_action(s.run, a))
		_holds[ann.slot] = a.hold_bit
		_holds[bob.slot] = a.hold_bit
		s.step(20)
		match why:
			"release":
				_holds[ann.slot] = 0
			"move":
				ann.at(s.run.tick).move(90.0, InputRecord.Gait.WALK, 20)
			"partner":
				_holds[bob.slot] = 0
		s.step(50)
		assert_eq(ends.size(), 1, "%s cancels" % why)
		assert_eq(LampOil.oil_in(flask), 1.0, "%s: nothing poured" % why)
		assert_almost_eq(lb.oil, 0.7, 0.01, "%s: nothing shared (it only burned)" % why)
