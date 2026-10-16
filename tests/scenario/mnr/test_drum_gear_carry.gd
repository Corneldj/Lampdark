extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-14 (Gameplay §3.3, §4.3): two miners carry the drum gear 30 tiles down a straight road in
## 15 s (2.0 tiles/s) to a tick, stepping 9 np every 10 ticks each, never knocking; and with one of
## them on a 120 ms link and the other on 40 ms, the same carry never knocks either.

const W = preload("res://tests/unit/mnr/load_world.gd")

const ROAD: int = 50


func before_all() -> void:
	assert_true(Tuning.load_server())


func _road() -> FixtureMap:
	var wall: String = "#".repeat(ROAD)
	var row: String = "#" + ".".repeat(ROAD - 2) + "#"
	return FixtureMap.from_ascii(PackedStringArray([wall, row, row, row, wall]))


## The gear at (6, 2.5) heading east, Ann east of it and Bob west, both holding its ends.
func _carry(run_seed: int, ann_rtt: int = 0, bob_rtt: int = 0) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": _road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(7, 2))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(4, 2))
	if ann_rtt > 0:
		ann.link(ann_rtt, 0.0)
	if bob_rtt > 0:
		bob.link(bob_rtt, 0.0)
	ann.at(s.run.tick).face(180.0)
	bob.at(s.run.tick).face(0.0)
	s.step(20)
	var gear: int = s.run.loads.place(s.run, ItemKinds.Kind.DRUM_GEAR, Vector2(6.0, 2.5), 0)
	assert_ne(gear, 0)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_true(s.run.loads.carrying(ann.entity_id) and s.run.loads.carrying(bob.entity_id), "both ends taken")
	return [s, ann, bob, gear]


## Both push east; the ticks from the gear's first move until it has gone 30 tiles.
func _thirty_tiles(s: Scenario, ann: MinerHandle, bob: MinerHandle, gear: int) -> int:
	var from: float = s.run.registry.get_entity(gear).position.x
	var first: Array[int] = [-1]
	var done: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var x: float = sc.run.registry.get_entity(gear).position.x
		if first[0] < 0 and x > from + 1e-6:
			first[0] = sc.run.tick - 1
		if done[0] < 0 and x >= from + 30.0 - 1e-6:
			done[0] = sc.run.tick - 1
	W.drive(s, ann, bob, 0.0, 340)
	s.step(360)
	s.on_tick = Callable()
	return done[0] - first[0] + 1


func test_two_carry_the_drum_gear_30_tiles_in_15_s() -> void:
	var w: Array = _carry(1521)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var gear: int = w[3]
	var from: int = s.run.noise.event_log.size()
	var ticks: int = _thirty_tiles(s, ann, bob, gear)
	gut.p("30 tiles in %d ticks" % ticks)
	assert_almost_eq(float(ticks), 300.0, 1.0, "15 s, to a tick")
	assert_eq(W.knocks_since(s, from), 0, "agreeing carriers never knock")
	var steps: Dictionary = {}
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == NoiseTypes.Type.STEP_DRUM_GEAR:
			assert_eq(e.level_np, 9.0)
			var list: Array = steps.get(e.source_entity, [])
			list.append(e.tick)
			steps[e.source_entity] = list
	assert_eq(steps.keys().size(), 2, "both carriers step")
	for raw: Variant in steps.values():
		var ticks_of: Array = raw
		assert_gte(ticks_of.size(), 30, "at least 30 steps over 30 tiles")
		for i: int in range(1, ticks_of.size()):
			assert_eq(int(Variants.number(ticks_of[i])) - int(Variants.number(ticks_of[i - 1])), 10, "a step every 10 ticks")


func test_unequal_links_never_knock() -> void:
	var w: Array = _carry(1522, 120, 40)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var gear: int = w[3]
	var from: int = s.run.noise.event_log.size()
	var ticks: int = _thirty_tiles(s, ann, bob, gear)
	gut.p("30 tiles in %d ticks with links of 120 and 40 ms" % ticks)
	assert_eq(W.knocks_since(s, from), 0, "lag alone never knocks")
	assert_almost_eq(float(ticks), 300.0, 2.0)
