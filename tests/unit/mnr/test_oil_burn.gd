extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-07: every cell of the fill table to within one tick (a full fount at wick down, normal and up,
## in rings 0-1, 2 and 3-4); shuttered, slotted and hooked lamps burn x0.5 at every wick; a lamp set
## down in ring 2 while its miner stands in ring 1 burns at ring 2's rate; zero oil is Dry.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const O = preload("res://tests/unit/mnr/oil_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_fill_table() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var lamps: Array[GauzeLamp] = []
	var expected: Array[int] = []
	var labels: Array[String] = []
	# §4.4 / §10.7: a fill lasts, by wick (down, normal, up), in rings 0-1, 2 and 3-4.
	var minutes: Dictionary = {0: [24.0, 12.0, 8.0], 2: [19.2, 9.6, 6.4], 3: [16.0, 8.0, 16.0 / 3.0]}
	for ring: int in [1, 2, 3]:
		var row: Array = minutes[0 if ring == 1 else ring]
		for wick: int in 3:
			var at: Vector2 = O.point_in_ring(ring) + Vector2(0, wick * 3)
			lamps.append(O.parked(s, at, wick))
			expected.append(roundi(float(Variants.number(row[wick])) * 60.0 * 20.0))
			labels.append("ring %d, wick %d" % [ring, wick])
	var dry_at: Dictionary = {}
	var start: int = s.run.tick
	s.run.lamps.lamp_changed.connect(func(l: GauzeLamp, what: StringName, _c: String) -> void:
		if what == &"dry" and not dry_at.has(l.uid):
			dry_at[l.uid] = s.run.tick - start)
	O.run_server(s, 24 * 60 * 20 + 40)
	for i: int in lamps.size():
		var got: int = int(Variants.number(dry_at.get(lamps[i].uid, -1)))
		assert_almost_eq(got, expected[i], 1, "%s: dry after %d ticks (%d expected)" % [labels[i], got, expected[i]])
		assert_eq(lamps[i].state(), GauzeLamp.State.DRY)
	assert_eq(expected[4], 11520, "normal in ring 2: 11,520 ticks")


func test_closed_states_burn_half() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var per_tick: float = 1.0 / 14400.0
	for wick: int in 3:
		var ann: MinerHandle = s.add_miner("m%d" % wick, a + Vector2i(wick * 3, 0))
		s.step(1)
		var shut: GauzeLamp = L.lit_in_hand(s, ann, wick)
		s.run.lamps.douse(s.run, shut, 0)
		var before: float = shut.oil
		s.step(100)
		assert_almost_eq(before - shut.oil, 100 * per_tick * 0.5, 1e-9, "shuttered at wick %d: x0.5" % wick)
		assert_true(s.run.lamps.slot(s.run, shut))
		before = shut.oil
		s.step(100)
		assert_almost_eq(before - shut.oil, 100 * per_tick * 0.5, 1e-9, "slotted at wick %d: x0.5" % wick)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(0, 2))
	s.step(1)
	for wick: int in 3:
		var hooked: GauzeLamp = L.lit_in_hand(s, bob, wick) if wick == 0 else s.run.lamps.lamp_in_hand(bob.entity_id)
		hooked.wick = wick
		s.run.inventory.begin_two_handed(s.run, bob.entity_id)
		s.step(1)
		var before: float = hooked.oil
		s.step(100)
		assert_eq(hooked.place, LampRules.Place.HOOK)
		assert_almost_eq(before - hooked.oil, 100 * per_tick * 0.5, 1e-9, "hooked at wick %d: x0.5" % wick)
		s.run.inventory.end_two_handed(bob.entity_id)


func test_set_down_burns_by_its_own_tile() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	var edge: Array[Vector2] = O.ring_edge(1)
	var lamp: GauzeLamp = O.parked(s, edge[1], LampRules.WICK_NORMAL)
	var held_side: GauzeLamp = O.parked(s, edge[0], LampRules.WICK_NORMAL)
	assert_eq(WorldCoords.ring_of_point(edge[1]), 2)
	assert_eq(WorldCoords.ring_of_point(edge[0]), 1)
	var before: Array[float] = [lamp.oil, held_side.oil]
	O.run_server(s, 200)
	assert_almost_eq(before[0] - lamp.oil, 200.0 / 14400.0 * 1.25, 1e-9, "the lamp in ring 2 drinks at ring 2's rate")
	assert_almost_eq(before[1] - held_side.oil, 200.0 / 14400.0, 1e-9, "a tile away, in ring 1, at ring 1's")


func test_dry_and_back() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.room()})
	var lamp: GauzeLamp = O.parked(s, Vector2(5.5, 3.5), LampRules.WICK_NORMAL, 10.0 / 14400.0)
	O.run_server(s, 12)
	assert_eq(lamp.state(), GauzeLamp.State.DRY, "zero oil: Dry")
	assert_eq(s.run.light.light_at(Vector2i(5, 3)), 0.0, "no light")
	assert_false(s.run.lamps.relight(s.run, lamp), "no path from Dry to Burning")
	assert_false(Relight.offered(lamp, Relight.FLINT), "no relight offered on a dry lamp")
	var flask: Item = s.run.inventory.world.make(ItemKinds.Kind.OIL_FLASK, 1, {"fill": 1.0})
	LampOil._add(s.run, lamp, 0.25)
	assert_eq(lamp.state(), GauzeLamp.State.OUT, "oil added: Out")
	assert_true(Relight.relight(s.run, lamp, Relight.RELIGHTER, 0))
	assert_eq(lamp.state(), GauzeLamp.State.SET_DOWN_OPEN, "relit")
	assert_eq(LampOil.oil_in(flask), 1.0)
