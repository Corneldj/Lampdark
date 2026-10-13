extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-04: a miner walks a straight road out from the shaft to 210 tiles; ring_for_miner changes
## exactly where FND-07's lookup does (80 and 200 tiles), and D changes with it.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_crossing() -> void:
	# A road along the shaft centre's row, from x 10 to x 232.
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 12:
		rows.append(("#".repeat(10) + "a" + ".".repeat(222) + "#") if y == 10 else "#".repeat(234))
	var s: Scenario = make({"seed": 1, "fixture": FixtureMap.from_ascii(rows)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 2000)
	var crossings: Array[Array] = []
	var last: Array[int] = [0]
	var mismatches: Array[int] = [0]
	var centre: Vector2 = Vector2(WorldIds.SHAFT_CENTRE_X2, WorldIds.SHAFT_CENTRE_Y2) / 2.0
	s.on_tick = func(sc: Scenario) -> void:
		var e: SimEntity = sc.run.registry.get_entity(ann.entity_id)
		var ring: int = Depth.ring_for_miner(sc.run, ann.entity_id)
		if ring != WorldCoords.ring_of_point(e.position):
			mismatches[0] += 1
		if ring != last[0]:
			crossings.append([ring, e.position.distance_to(centre), Depth.pull_factor(ring)])
			last[0] = ring
	var reached: Array[float] = [0.0]
	while reached[0] < 210.0 and s.run.tick < 4000:
		s.step(20)
		reached[0] = s.run.registry.get_entity(ann.entity_id).position.distance_to(centre)
	gut.p("crossings (ring, distance, D): %s" % [crossings])
	assert_eq(mismatches[0], 0, "always FND-07's ring")
	assert_eq(crossings.size(), 2, "two crossings on the way to 210 tiles")
	var first: Array = crossings[0]
	var second: Array = crossings[1]
	assert_eq(int(Variants.number(first[0])), 1)
	assert_between(Variants.number(first[1]), 80.0, 80.5, "ring 1 from 80 tiles")
	assert_eq(Variants.number(first[2]), 1.0, "D 1.0")
	assert_eq(int(Variants.number(second[0])), 2)
	assert_between(Variants.number(second[1]), 200.0, 200.5, "ring 2 from 200 tiles")
	assert_eq(Variants.number(second[2]), 1.5, "D 1.5")
