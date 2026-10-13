extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-08: sources x states x causes. Trembling within 20 tiles of an awake Moth (not 21; never a
## sleeping one; exactly 30 ticks for a stir); guttering within 10 tiles of the Stythe's tell (a
## stand-in cause until CRT-14) with radius x0.7 (a wick-up core 3.3 -> 2.31); the blue cap only on
## gauze flames in firedamp; blackdamp's shrink at 10% of R a second; non-flames never get a state
## or a radius change; low oil shows nothing; every change has a logged cause.

const L = preload("res://tests/unit/mnr/lamp_world.gd")

const ROWS_W: int = 60


func before_all() -> void:
	assert_true(Tuning.load_server())


func _hall() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(ROWS_W + 2)])
	for _y: int in 5:
		rows.append("#" + ".".repeat(ROWS_W) + "#")
	rows.append("#".repeat(ROWS_W + 2))
	return FixtureMap.from_ascii(rows)


## A lit lamp lying on the floor at a tile's centre.
func _lamp(s: Scenario, tile: Vector2i, wick: int = LampRules.WICK_NORMAL) -> GauzeLamp:
	return s.run.lamps.create(s.run, 1.0, 3, true, wick, Vector2(tile) + Vector2(0.5, 0.5))


func _bits(s: Scenario, l: GauzeLamp) -> int:
	return s.run.flame_states.flags_of(l.source)


func test_trembling_reach_of_an_awake_moth() -> void:
	for gap: int in [20, 21]:
		var s: Scenario = make({"seed": gap, "fixture": _hall()})
		s.step(1)
		var l: GauzeLamp = _lamp(s, Vector2i(5, 3))
		s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(5 + gap, 3))
		var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
		s.step(2)
		assert_eq(_bits(s, l), 0, "a sleeping Moth causes nothing")
		m.waker = {}
		m.enter(s.run, &"prowl", "test")
		m.awake.begin(s.run, m, false)
		s.step(1)
		var d: float = m.position(s.run).distance_to(Vector2(5.5, 3.5))
		assert_eq((_bits(s, l) & FlameFlags.TREMBLE) != 0, d <= 20.0 + 1e-9, "%d tiles (now %.2f)" % [gap, d])


func test_a_stir_trembles_for_exactly_30_ticks() -> void:
	var s: Scenario = make({"seed": 3, "fixture": _hall()})
	s.step(1)
	var l: GauzeLamp = _lamp(s, Vector2i(5, 3))
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(20, 3))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	s.step(2)
	m._stir(s.run, MothSleep.Cause.CLOCK)
	var trembling: int = 0
	for _i: int in 80:
		s.step(1)
		if (_bits(s, l) & FlameFlags.TREMBLE) != 0:
			trembling += 1
	assert_eq(trembling, Tuning.ticks(&"moth.stir_tell_s"), "the stir's 1.5 s, exactly")
	assert_true(m.state.name == &"settling" or m.state.name == &"sleeping", "it settled, never woke: no light reached it")


## A stand-in for CRT-14's Stythe in an active state at `at`.
func _stythe(s: Scenario, at: Vector2, active: Array[bool]) -> void:
	s.run.flame_states.causes.append(func(_run: RunState) -> Array:
		return [{"state": FlameFlags.GUTTER, "point": at, "reach": Tuning.f(&"stythe.tell_reach_tiles"), "cause": "stythe#1"}] if active[0] else [])


func test_guttering_cuts_the_radius_and_the_core() -> void:
	var s: Scenario = make({"seed": 4, "fixture": _hall()})
	s.step(1)
	var near: GauzeLamp = _lamp(s, Vector2i(5, 3), LampRules.WICK_UP)
	var far: GauzeLamp = _lamp(s, Vector2i(40, 3), LampRules.WICK_UP)
	var candle: int = s.run.light.grid.add_point("candle", LbLightGrid.COLOUR_AMBER, 0, LbLightGrid.FLAG_FLAME, 1.5, 1.0, Vector2(8.5, 3.5), 0)
	var active: Array[bool] = [false]
	_stythe(s, Vector2(15.5, 3.5), active)
	s.step(2)
	assert_eq(_bits(s, near), 0, "lurking, circling or shadowing: nothing gutters")
	var r0: float = float(Variants.number(s.run.light.grid.source_info(near.source)["radius"]))
	var probe: Vector2i = Vector2i(10, 3)
	assert_gt(s.run.light.grid.value(probe), 0, "5 tiles off: lit at 5.5")
	active[0] = true
	s.step(2)
	assert_eq(s.run.light.grid.value(probe), 0, "the grid itself shrinks: dark at 3.85")
	assert_ne(_bits(s, near) & FlameFlags.GUTTER, 0, "10 tiles: gutters")
	assert_ne(s.run.flame_states.flags_of(candle) & FlameFlags.GUTTER, 0, "a candle gutters too")
	assert_eq(_bits(s, far) & FlameFlags.GUTTER, 0, "25 tiles: not")
	var core_frac: float = Tuning.f(&"light.core_fraction")
	assert_almost_eq(r0 * core_frac, 3.3, 1e-6, "a wick-up core is 3.3 tiles")
	var lit_r: float = _effective_radius(s, near)
	assert_almost_eq(lit_r, r0 * 0.7, 1e-3, "radius x0.7 on the grid")
	assert_almost_eq(lit_r * core_frac, 2.31, 1e-3, "the core falls to 2.31 tiles")
	active[0] = false
	s.step(2)
	assert_eq(_bits(s, near), 0)
	assert_almost_eq(_effective_radius(s, near), r0, 1e-6, "back to full")


## The radius the grid lays this source at now (VIS-02's multiplier applied).
func _effective_radius(s: Scenario, l: GauzeLamp) -> float:
	var info: Dictionary = s.run.light.grid.source_info(l.source)
	return float(Variants.number(info["radius"])) * float(Variants.number(info.get("radius_mult", 1.0)))


func test_the_blue_cap_is_gauze_only() -> void:
	var s: Scenario = make({"seed": 5, "fixture": _hall()})
	s.step(1)
	var l: GauzeLamp = _lamp(s, Vector2i(5, 3))
	var candle: int = s.run.light.grid.add_point("candle", LbLightGrid.COLOUR_AMBER, 0, LbLightGrid.FLAG_FLAME, 1.5, 1.0, Vector2(6.5, 3.5), 0)
	s.run.flame_states.firedamp_at = func(tile: Vector2i) -> bool: return tile.x <= 10
	s.step(2)
	assert_eq(_bits(s, l), FlameFlags.CAP, "a gauze flame in firedamp: the cap")
	assert_eq(s.run.flame_states.flags_of(candle) & FlameFlags.CAP, 0, "a candle never")
	assert_almost_eq(_effective_radius(s, l), float(Variants.number(s.run.light.grid.source_info(l.source)["radius"])), 1e-9,
		"the cap never changes the grid")


func test_blackdamp_shrinks_ten_percent_a_second() -> void:
	var s: Scenario = make({"seed": 6, "fixture": _hall()})
	s.step(1)
	var l: GauzeLamp = _lamp(s, Vector2i(5, 3))
	s.step(1)
	var entered: int = s.run.tick
	s.run.flame_states.blackdamp_s = func(_id: int, _tile: Vector2i) -> float: return (s.run.tick - entered) / Tuning.f(&"net.tick_hz")
	var r0: float = float(Variants.number(s.run.light.grid.source_info(l.source)["radius"]))
	s.step(21)
	assert_ne(_bits(s, l) & FlameFlags.SHRINK, 0)
	var t: float = (s.run.tick - 1 - entered) / Tuning.f(&"net.tick_hz")
	assert_almost_eq(_effective_radius(s, l), r0 * (1.0 - 0.10 * t), 1e-3, "10% of R a second")
	s.step(200)
	assert_almost_eq(_effective_radius(s, l), 0.0, 1e-9, "out of light at 10 s")


func test_non_flames_never_change() -> void:
	var s: Scenario = make({"seed": 7, "fixture": _hall()})
	s.step(1)
	var grid: LbLightGrid = s.run.light.grid
	var electric: int = grid.add_point("electric_lamp", LbLightGrid.COLOUR_WHITE, 0, 0, 4.0, 1.0, Vector2(5.5, 3.5), 0)
	var flare: int = grid.add_point("flare", LbLightGrid.COLOUR_AMBER, 0, LbLightGrid.FLAG_FLAME | LbLightGrid.FLAG_NO_FLAME_STATES, 14.0, 1.0, Vector2(6.5, 3.5), 0)
	var flash: int = grid.add_point("muzzle_flash", LbLightGrid.COLOUR_WHITE, 0, 0, 6.0, 1.0, Vector2(7.5, 3.5), 0)
	var low: GauzeLamp = s.run.lamps.create(s.run, 0.03, 3, true, LampRules.WICK_NORMAL, Vector2(9.5, 3.5))
	s.step(2)
	assert_eq(_bits(s, low), 0, "low oil shows nothing")
	var active: Array[bool] = [true]
	_stythe(s, Vector2(6.5, 3.5), active)
	s.run.flame_states.firedamp_at = func(_tile: Vector2i) -> bool: return true
	s.run.flame_states.blackdamp_s = func(_id: int, _tile: Vector2i) -> float: return 3.0
	s.step(3)
	for id: int in [electric, flare, flash]:
		assert_eq(s.run.flame_states.flags_of(id), 0, "%s: no state" % grid.source_info(id)["kind"])
		assert_almost_eq(float(Variants.number(grid.source_info(id).get("radius_mult", 1.0))), 1.0, 1e-9, "and no radius change")


func test_every_change_has_a_cause() -> void:
	var s: Scenario = make({"seed": 8, "fixture": _hall()})
	s.step(1)
	var l: GauzeLamp = _lamp(s, Vector2i(5, 3))
	var active: Array[bool] = [false]
	_stythe(s, Vector2(10.5, 3.5), active)
	for i: int in 6:
		active[0] = i % 2 == 0
		s.step(5)
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(20, 3))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	m._stir(s.run, MothSleep.Cause.CLOCK)
	s.step(60)
	assert_gt(s.run.flame_states.changes.size(), 6)
	for c: Dictionary in s.run.flame_states.changes:
		assert_false(str(c["cause"]).is_empty(), "%s %s at %d has a cause" % [c["state"], "on" if c["on"] else "off", c["tick"]])
	var _keep: GauzeLamp = l


func test_a_hands_belt_lamp_shows_every_state() -> void:
	var s: Scenario = make({"seed": 9, "fixture": _hall()})
	var hand: MinerHandle = s.add_miner("hand", Vector2i(5, 3))
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, hand)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	assert_true(s.run.inventory.begin_two_handed(s.run, hand.entity_id), "on the belt hook")
	var active: Array[bool] = [true]
	_stythe(s, Vector2(8.5, 3.5), active)
	s.run.flame_states.firedamp_at = func(_tile: Vector2i) -> bool: return true
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(15, 3))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	m._stir(s.run, MothSleep.Cause.CLOCK)
	s.step(3)
	var want: int = FlameFlags.TREMBLE | FlameFlags.GUTTER | FlameFlags.CAP
	assert_eq(_bits(s, l) & want, want)
	assert_eq(s.run.flame_states.entity_flags(hand.entity_id) & want, want, "shown on the Hand's identity record")
