extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: in its active states the Stythe snuffs every 40 ticks at crew count 1-2, 32 at 3 or more,
## and 32 in its territory: the nearest flame within 3 tiles in its line of sight, shuttered or not;
## flares, emergency lamps and egg-glow never; and nothing in Lurk, Circle or Shadow.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## A burning lamp lying shuttered: a flame it snuffs, and no light to push it off its tile.
func _lamp(s: Scenario, at: Vector2) -> GauzeLamp:
	var l: GauzeLamp = s.run.lamps.create(s.run, 1.0, 0, true, LampRules.WICK_NORMAL, at)
	assert(s.run.lamps.shutter_in_place(s.run, l, 0), "shuttered where it lies")
	return l


## Ticks between the first two snuffs in Hunt with lamps lying round it.
func _interval(s: Scenario, st: StytheCreature) -> int:
	var at: Vector2 = st.position(s.run)
	for dx: float in [-2.5, 2.5, -1.5]:
		_lamp(s, at + Vector2(dx, 0.0))
	s.step(10)  # the shutters close (MNR-06's step), so no light pushes it off its tile
	st.enter(s.run, &"hunt", "test")
	var before: int = st.snuff.history.size()
	for _i: int in 120:
		s.step(1)
		if st.snuff.history.size() >= before + 2:
			break
	var h: Array[Dictionary] = st.snuff.history.slice(before)
	return int(Variants.number(h[1]["tick"])) - int(Variants.number(h[0]["tick"])) if h.size() >= 2 else -1


func test_intervals_by_crew_and_territory() -> void:
	var s: Scenario = make({"seed": 1231, "fixture": W.road(60), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(30, 2))
	W.miner(s, "a", Vector2i(2, 2))
	s.step(2)
	assert_eq(_interval(s, st), 40, "crew of 1: 2.0 s")
	var s3: Scenario = make({"seed": 1232, "fixture": W.road(60), "overrides": W.ON})
	var st3: StytheCreature = W.stythe(s3, Vector2i(30, 2))
	for i: int in 3:
		W.miner(s3, "m%d" % i, Vector2i(2 + i * 2, 2))
	s3.step(2)
	assert_eq(_interval(s3, st3), 32, "crew of 3: 1.6 s")
	var st_t: Scenario = make({"seed": 1233, "fixture": W.road(60), "overrides": W.ON})
	var stt: StytheCreature = W.stythe(st_t, Vector2i(30, 2), Vector2i(30, 2))
	W.miner(st_t, "a", Vector2i(2, 2))
	st_t.step(2)
	assert_eq(_interval(st_t, stt), 32, "in its territory: 1.6 s")


func test_nearest_in_reach_and_sight() -> void:
	var rows: PackedStringArray = ["#" .repeat(42), "#" + ".".repeat(40) + "#", "#" + ".".repeat(18) + "#" + ".".repeat(21) + "#",
		"#" + ".".repeat(40) + "#", "#".repeat(42)]
	var s: Scenario = make({"seed": 1234, "fixture": FixtureMap.from_ascii(rows), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(18, 2))
	s.step(1)
	var at: Vector2 = st.position(s.run)
	var near: GauzeLamp = _lamp(s, at + Vector2(-2.0, 0.0))
	var nearer: GauzeLamp = _lamp(s, at + Vector2(0.0, -1.0))
	var beyond: GauzeLamp = _lamp(s, at + Vector2(-3.6, 0.0))
	var hidden: GauzeLamp = _lamp(s, at + Vector2(2.0, 0.0))  # behind the pillar at (19, 2)
	s.step(8)
	st.enter(s.run, &"hunt", "test")
	s.step(41)
	assert_false(nearer.burning(), "the nearest first (shuttered: a flame all the same)")
	assert_true(near.burning() and beyond.burning() and hidden.burning(), "one a snuff")
	s.step(40)
	assert_false(near.burning(), "then the next nearest")
	s.step(120)
	assert_true(beyond.burning(), "never beyond 3 tiles")
	assert_true(hidden.burning(), "never out of its sight")


func test_beyond_it_and_never_while_idle() -> void:
	var s: Scenario = make({"seed": 1235, "fixture": W.road(60), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(30, 2))
	s.step(1)
	var at: Vector2 = st.position(s.run)
	var flare: Item = s.run.inventory.world.make(ItemKinds.Kind.FLARE, 1, {"lit": true, "burn_ticks": 2000})
	s.run.inventory.world.put(s.run, flare, at + Vector2(1.0, 0.0))
	s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, 0.6, [Vector2i(at) + Vector2i(-2, 0)])
	s.run.light.grid.add_point("egg_glow", LbLightGrid.COLOUR_EGG_GLOW, 0, 0, 1.5, 0.2, at + Vector2(0.0, 0.0), 0)
	s.step(2)
	st.enter(s.run, &"hunt", "test")
	s.step(100)
	assert_eq(st.snuff.history.size(), 0, "flares, emergency lamps and egg-glow are beyond it")
	assert_true(HandsAndBelt.burning_flare(flare))
	var lamp: GauzeLamp = _lamp(s, at + Vector2(0.0, 0.0) + Vector2(-1.0, 0.0))
	for state: StringName in [&"lurk", &"circle", &"shadow"]:
		st.enter(s.run, state, "test")
		s.step(100)
		assert_true(lamp.burning(), "never snuffs in %s" % state)
	assert_eq(st.snuff.history.size(), 0)
