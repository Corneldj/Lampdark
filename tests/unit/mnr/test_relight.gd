extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-07: the flint takes 30 ticks at a crouch's pace or slower, spends one notch and clicks once at
## 9 np, and the lamp comes back open at its old wick; it is not offered with no notches, on a dry
## lamp, or with the free hand blocked; in blackdamp it clicks and spends nothing. A candle (1 s) and
## a passed flame (3 s) relight and report a naked flame. Notches never rise.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	ann.at(0).lamp(false, LampRules.WICK_UP)
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.run.lamps.snuff(s.run, l, "test")
	s.step(1)
	return [s, ann, l]


func _clicks(s: Scenario) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == NoiseTypes.Type.FLINT_CLICK:
			out.append(e)
	return out


func test_flint() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	var seen: Array[TimedAction] = []
	s.on_tick = func(sc: Scenario) -> void:
		var act: TimedAction = sc.run.inventory.actions.get(ann.entity_id, null)
		if act != null and not seen.has(act):
			seen.append(act)
	ann.at(s.run.tick).hold(InputRecord.HOLD_RELIGHT, 40)
	s.step(50)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0].verb, &"flint")
	assert_eq(seen[0].ticks_needed, 30, "1.5 s")
	assert_eq(l.state(), GauzeLamp.State.OPEN, "relit, open")
	assert_eq(l.wick, LampRules.WICK_UP, "at its old wick")
	assert_eq(l.notches, 2, "one notch")
	var clicks: Array[NoiseSystem.Event] = _clicks(s)
	assert_eq(clicks.size(), 1, "one click")
	assert_eq(clicks[0].level_np, 9.0)


func test_flint_refused() -> void:
	# Running: above a crouch's pace it never completes.
	var parts: Array = _setup(2)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 60)
	ann.at(s.run.tick + 2).hold(InputRecord.HOLD_RELIGHT, 50)
	s.step(70)
	assert_eq(l.state(), GauzeLamp.State.OUT, "running: no relight")
	assert_eq(l.notches, 3)
	# No notches, a dry lamp, a blocked free hand: not offered.
	for case: String in ["notches", "dry", "revolver"]:
		var p2: Array = _setup(3 + case.length())
		var s2: Scenario = p2[0]
		var b: MinerHandle = p2[1]
		var l2: GauzeLamp = p2[2]
		match case:
			"notches":
				l2.notches = 0
			"dry":
				l2.oil = 0.0
				l2.phase = LampRules.Phase.DRY
			"revolver":
				W.belt(s2, b.entity_id).free_hand = s2.run.inventory.world.make(ItemKinds.Kind.REVOLVER)
		b.at(s2.run.tick).hold(InputRecord.HOLD_RELIGHT, 40)
		s2.step(50)
		assert_ne(l2.state(), GauzeLamp.State.OPEN, "%s: not offered" % case)
		assert_eq(_clicks(s2).size(), 0, "%s: no click" % case)


func test_flint_in_blackdamp_clicks_only() -> void:
	var parts: Array = _setup(4)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	s.run.lamps.in_blackdamp = func(_t: Vector2i) -> bool: return true
	ann.at(s.run.tick).hold(InputRecord.HOLD_RELIGHT, 40)
	s.step(50)
	assert_eq(_clicks(s).size(), 1, "it clicks (9 np)")
	assert_eq(l.notches, 3, "no notch spent")
	assert_eq(l.state(), GauzeLamp.State.OUT, "the lamp stays Out")


func test_candle_and_passed_flame() -> void:
	var parts: Array = _setup(5)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	var flames: Array[String] = []
	s.run.lamps.naked_flame.connect(func(_t: Vector2i, cause: String) -> void: flames.append(cause))
	var a: Vector2i = s.fixture.spot("a")
	s.run.inventory.world.put(s.run, s.run.inventory.world.make(ItemKinds.Kind.CANDLE, 1, {"lit": true}), Vector2(a) + Vector2(1.5, 0.5))
	var act: TimedAction = Relight.candle_action(s.run, ann.entity_id, ann.entity_id)
	assert_eq(act.ticks_needed, 20, "1 s")
	assert_true(s.run.inventory.start_action(s.run, act))
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return InputRecord.HOLD_INTERACT if slot == ann.slot else 0
	s.step(22)
	assert_eq(l.state(), GauzeLamp.State.OPEN, "a candle relights it")
	assert_eq(l.notches, 3, "no notch")
	assert_eq(flames, ["candle"] as Array[String], "a naked flame")
	# Passed flame: bob's burning lamp to ann's out one.
	s.run.lamps.snuff(s.run, l, "test")
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(1, 1))
	s.step(1)
	L.lit_in_hand(s, bob)
	var pass_act: TimedAction = Relight.pass_flame_action(s.run, bob.entity_id, ann.entity_id)
	assert_eq(pass_act.ticks_needed, 60, "3 s")
	assert_true(s.run.inventory.start_action(s.run, pass_act))
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return InputRecord.HOLD_INTERACT if slot in [ann.slot, bob.slot] else 0
	s.step(62)
	assert_eq(l.state(), GauzeLamp.State.OPEN, "a passed flame relights it")
	assert_eq(flames, ["candle", "passed_flame"] as Array[String])


func test_notches_never_rise() -> void:
	var s: Scenario = make({"seed": 6, "fixture": W.room()})
	var lamps: Array[GauzeLamp] = []
	for i: int in 4:
		lamps.append(s.run.lamps.create(s.run, 0.5, 3, true, LampRules.WICK_NORMAL, Vector2(3.5 + i, 2.5)))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 707
	var methods: Array[StringName] = [Relight.FLINT, Relight.CANDLE, Relight.PASSED, Relight.RELIGHTER]
	var last: Array[int] = [3, 3, 3, 3]
	var rises: int = 0
	for _i: int in 10000:
		var k: int = rng.randi_range(0, 3)
		var l: GauzeLamp = lamps[k]
		match rng.randi_range(0, 4):
			0:
				s.run.lamps.snuff(s.run, l, "test")
			1:
				Relight.relight(s.run, l, methods[rng.randi_range(0, 3)], 0)
			2:
				l.oil = 0.0
				s.run.lamps.mark_dry(s.run, l)
			3:
				LampOil._add(s.run, l, rng.randf_range(0.0, 1.0))
			4:
				s.run.lamps.relight(s.run, l)
		for j: int in 4:
			if lamps[j].notches > last[j]:
				rises += 1
			last[j] = lamps[j].notches
	assert_eq(rises, 0, "over 10,000 random actions no notch count ever rose")
	gut.p("notches left: %s" % [last])
