extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-05: 10,000 ticks of random ring input by miner A on miner B (opening, picking any option,
## holding and releasing at random; B sometimes holding interact) never open B's lamp, raise B's wick
## or lower B's oil, except a share completed with B holding throughout.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")

const TICKS: int = 10000


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_fuzz() -> void:
	var s: Scenario = make({"seed": 77, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var a: MinerHandle = pair[0]
	var b: MinerHandle = pair[1]
	var la: GauzeLamp = L.lit_in_hand(s, a)
	var lb: GauzeLamp = L.lit_in_hand(s, b)
	la.oil = 1.0
	lb.oil = 0.6
	var inv: InventorySystem = s.run.inventory
	assert_true(inv.give(s.run, a.entity_id, inv.world.make(ItemKinds.Kind.OIL_FLASK, 1, {"fill": 1.0})))
	var shares: Array[int] = []
	var share_ends: Array[String] = []
	var share_starts: Array[int] = [0]
	var opens: Array[int] = [0]
	s.run.ring.opened.connect(func(actor: int, _t: int) -> void:
		if actor == a.entity_id:
			opens[0] += 1)
	var reg: RingOptions = s.run.ring.registry
	var share: RingOptions.Option = reg.options["share_oil"]
	var make_share: Callable = share.make
	share.make = func(run: RunState, actor: int, target: int) -> TimedAction:
		var act: TimedAction = make_share.call(run, actor, target)
		act.completed.connect(func(_x: TimedAction) -> void: shares.append(run.tick))
		act.cancelled.connect(func(_x: TimedAction, why: StringName) -> void: share_ends.append(str(why)))
		share_starts[0] += 1
		return act
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5150
	var violations: Array[String] = []
	var per_tick: float = 1.0 / 14400.0 * 1.5
	var was_closed: bool = lb.shutter_closed
	var was_wick: int = lb.wick
	var was_oil: float = lb.oil
	# A new hold cuts short the one before, so each miner finishes a hold before the next input.
	var a_busy: Array[int] = [0]
	var b_busy: Array[int] = [0]
	for t: int in TICKS:
		var roll: int = rng.randi_range(0, 9)
		if s.run.tick < a_busy[0] and roll != 5:
			roll = 9
		if s.run.tick < b_busy[0] and roll == 5:
			roll = 9
		match roll:
			0, 1:
				var tap: int = rng.randi_range(1, 3)
				a.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, tap)
				a_busy[0] = s.run.tick + tap + 2
			2:
				var offered: Array = Variants.array(a.connection.ring.get("options", []))
				if not offered.is_empty():
					var pick: int = rng.randi_range(0, offered.size() - 1)
					# Half the time she picks the share if it is there, so shares get exercised.
					if offered.has("share_oil") and rng.randi_range(0, 1) == 0:
						pick = offered.find("share_oil")
					a.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, pick)
			3, 4:
				var hold: int = rng.randi_range(5, 90)
				a.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, hold)
				a_busy[0] = s.run.tick + hold + 2
				# Half the time B joins in (a share then can complete), for as long or a little less.
				if rng.randi_range(0, 1) == 0 and s.run.tick >= b_busy[0]:
					var b_hold: int = hold - rng.randi_range(0, 4)
					b.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, b_hold)
					b_busy[0] = s.run.tick + b_hold + 2
			5:
				var solo: int = rng.randi_range(5, 70)
				b.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, solo)
				b_busy[0] = s.run.tick + solo + 2
		s.step(1)
		if was_closed and not lb.shutter_closed:
			violations.append("tick %d: B's lamp opened" % s.run.tick)
		if lb.wick > was_wick:
			violations.append("tick %d: B's wick raised" % s.run.tick)
		if lb.oil < was_oil - per_tick - 1e-9 and not shares.has(s.run.tick - 1) and not shares.has(s.run.tick):
			violations.append("tick %d: B's oil fell %.4f with no share" % [s.run.tick, was_oil - lb.oil])
		if not lb.burning() and lb.phase == LampRules.Phase.DRY:
			LampOil._add(s.run, lb, 0.5)
		was_closed = lb.shutter_closed
		was_wick = lb.wick
		was_oil = lb.oil
	assert_eq(violations, [] as Array[String])
	assert_gt(shares.size(), 0, "the fuzz reached completed shares")
	gut.p("opens %d, share starts %d, cancelled %d" % [opens[0], share_starts[0], share_ends.size()])
	gut.p("fuzz: %d ticks, %d shares completed, B's lamp %s" % [TICKS, shares.size(), GauzeLamp.State.find_key(lb.state())])
