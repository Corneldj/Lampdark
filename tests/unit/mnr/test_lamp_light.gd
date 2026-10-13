extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-06: radii and cores by state (§4.4's table); VIS-02's falloff puts 0.60 within 0.9, 1.4
## and 1.9 tiles by wick; the hook lights 2.5 at every wick and 0 shuttered; a slotted lamp gives
## no light but is still a flame; carried lamps are tagged with their holder, unheld ones not.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _flames(s: Scenario) -> PackedInt64Array:
	return s.run.light.grid.flame_sources(Rect2(-100, -100, 200, 200))


func test_radius_and_core_by_wick() -> void:
	var radii: Array[float] = [2.5, 4.0, 5.5]
	var cores: Array[float] = [1.5, 2.4, 3.3]
	for wick: int in 3:
		var s: Scenario = make({"seed": 10 + wick, "fixture": W.room()})
		var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
		s.step(1)
		var l: GauzeLamp = L.lit_in_hand(s, ann, wick)
		s.step(2)
		assert_almost_eq(s.run.light.grid.owned_radius(ann.entity_id), radii[wick], 1e-6, "open, wick %d" % wick)
		assert_almost_eq(LampRules.core(LampRules.wick_radius(wick)), cores[wick], 1e-6, "core, wick %d" % wick)
		assert_eq(l.source_flags & LbLightGrid.FLAG_CARRIED, LbLightGrid.FLAG_CARRIED, "carried, with its holder")
		s.run.lamps.douse(s.run, l, 0)
		s.step(2)
		assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0, "shuttered: no light")
		assert_true(_flames(s).has(l.source), "a shuttered lamp is still a flame")


func test_reach_of_060() -> void:
	var expected: Array[float] = [0.9, 1.4, 1.9]
	for wick: int in 3:
		var r: float = LampRules.wick_radius(wick)
		var reach: float = 0.0
		var d: float = 0.0
		while d <= r:
			if LbLightMath.falloff_milli(d, r, 1.0, Tuning.f(&"light.core_fraction"), Tuning.f(&"light.core_value"), Tuning.f(&"light.edge_value")) >= 600:
				reach = d
			d += 0.001
		assert_almost_eq(reach, expected[wick], 0.05, "0.60 reach at wick %d" % wick)
		gut.p("wick %d: radius %.1f, 0.60 to %.3f tiles" % [wick, r, reach])


func test_hook_and_slot() -> void:
	var s: Scenario = make({"seed": 20, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(2)
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	for wick: int in [LampRules.WICK_UP, LampRules.WICK_NORMAL, LampRules.WICK_DOWN]:
		l.wick = wick
		s.step(2)
		assert_eq(l.place, LampRules.Place.HOOK)
		assert_almost_eq(s.run.light.grid.owned_radius(ann.entity_id), 2.5, 1e-6, "hooked: 2.5 at wick %d" % wick)
	s.run.lamps.douse(s.run, l, 0)
	s.step(2)
	assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0, "the hook's shutter still works")
	s.run.inventory.end_two_handed(ann.entity_id)
	s.step(2)
	assert_eq(l.state(), GauzeLamp.State.SHUTTERED, "back to the hand as it was: shuttered")
	assert_true(s.run.lamps.slot(s.run, l))
	s.step(2)
	assert_eq(l.state(), GauzeLamp.State.SLOTTED)
	assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0, "slotted: no light")
	assert_true(_flames(s).has(l.source), "slotted: still a flame VIS-02 finds")


func test_unheld_is_nobodys() -> void:
	var s: Scenario = make({"seed": 21, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(1)
	assert_true(s.run.lamps.set_down(s.run, l, a + Vector2i(2, 0)))
	s.step(2)
	assert_eq(l.state(), GauzeLamp.State.SET_DOWN_OPEN)
	assert_eq(l.source_owner, 0, "an unheld lamp belongs to nobody")
	assert_eq(l.source_flags & LbLightGrid.FLAG_UNHELD, LbLightGrid.FLAG_UNHELD)
	assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0)
	assert_almost_eq(s.run.light.light_at(a + Vector2i(2, 0)), 1.0, 1e-3, "it keeps lighting at its wick")
	assert_gte(s.run.light.light_at(a + Vector2i(5, 0)), 0.30 - 1e-9, "core 3.3 at wick up")
