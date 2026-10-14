extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-03: four miners walk from base camp to every chamber and dead end of the grey box and back
## (the air door worked open first), each on GEN-01's path queries through the kit's walker.

const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_four_walk_to_every_chamber_and_dead_end_and_back() -> void:
	var s: Scenario = make({"seed": 33, "fixture": MAP})
	var targets: Array[Vector2i] = M1GreyboxCheck.walk_targets(s.mine, MAP)
	gut.p("targets: %s" % [targets])
	assert_gte(targets.size(), 6, "chambers and dead ends")
	# Base camp's floor, four apart.
	var inside: Array = Basecamp.inside_tiles(FixedMapLoader.run_seed(FixedMapLoader.manifest(MAP)),
		FixedMapLoader.blind_side(FixedMapLoader.manifest(MAP))).keys()
	inside.sort()
	var starts: Array[Vector2i] = []
	for raw: Variant in inside:
		var t: Vector2i = raw
		var last: Vector2i = starts.back() if not starts.is_empty() else Vector2i(-99, -99)
		if s.mine.native.is_walkable(t) and Vector2(t).distance_to(Vector2(last)) > 3.0:
			starts.append(t)
		if starts.size() == 4:
			break
	var miners: Array[MinerHandle] = []
	for i: int in 4:
		miners.append(s.add_miner("m%d" % i, starts[i]))
	s.step(3)
	for raw: Variant in s.run.air_doors.doors.values():
		var d: AirDoorSystem.Door = raw
		s.run.air_doors._flip(s.run, d, true)  # the hoard is behind the door: worked open first
	# Each miner's legs: a target, home, the next target, home.
	var legs: Array[Array] = [[], [], [], []]
	for i: int in targets.size():
		Variants.array(legs[i % 4]).append_array([targets[i], starts[i % 4]])
	var reached: Dictionary = {}
	var state: Array[int] = [0, 0, 0, 0]
	var started: Array[bool] = [false, false, false, false]
	var stuck: Array[String] = []
	for i: int in 4:
		var first: Array = legs[i]
		if not first.is_empty():
			var goal: Vector2i = first[0]
			miners[i].at(s.run.tick + 1).walk_to(goal)
			started[i] = true
	s.on_tick = func(sc: Scenario) -> void:
		for i: int in 4:
			var mine_legs: Array = legs[i]
			if state[i] >= mine_legs.size():
				continue
			var target: Vector2i = mine_legs[state[i]]
			var here: Vector2i = sc.run.registry.get_entity(miners[i].entity_id).tile()
			if here == target:
				if state[i] % 2 == 0:
					reached[target] = true
				state[i] += 1
				if state[i] < mine_legs.size():
					var next_goal: Vector2i = mine_legs[state[i]]
					miners[i].at(sc.run.tick + 1).walk_to(next_goal)
			elif miners[i].inputs.walk_at(sc.run.tick).is_empty() and sc.run.tick > 10:
				stuck.append("m%d stopped at %s short of %s" % [i, here, target])
				state[i] = mine_legs.size()
	var done: bool = s.run_until(func(_sc: Scenario) -> bool:
		for i: int in 4:
			if state[i] < Variants.array(legs[i]).size():
				return false
		return true, 30000)
	s.on_tick = Callable()
	gut.p("all legs walked by tick %d; stuck: %s" % [s.run.tick, stuck])
	assert_true(done, "every leg walked")
	assert_eq(stuck, [] as Array[String])
	for t: Vector2i in targets:
		assert_true(reached.has(t), "%s reached" % t)
	for i: int in 4:
		assert_eq(s.run.registry.get_entity(miners[i].entity_id).tile(), starts[i], "m%d is home" % i)
