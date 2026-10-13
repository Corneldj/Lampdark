extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-01: a listener-centred tell's points are chosen around the listener, so over 1,000 random
## placements the bearing from the listener to the mean of their points says nothing of the
## bearing to the creature (mean absolute error 90 +/- 10 degrees). The cue carries the tell's
## kind and the points only.

const W = preload("res://tests/scenario/creatures/creature_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_bearings() -> void:
	var s: Scenario = make({"seed": 31, "fixture": W.hall()})
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(20, 9))
	var moth: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 31
	var total: float = 0.0
	var n: int = 0
	for i: int in 1000:
		var listener: Vector2 = Vector2(rng.randf_range(1.5, 38.5), rng.randf_range(1.5, 18.5))
		var creature_at: Vector2 = Vector2(rng.randf_range(1.5, 38.5), rng.randf_range(1.5, 18.5))
		if listener.distance_to(creature_at) < 2.0:
			continue
		var points: Array[Vector2i] = Tell.points_around(s.run, moth.rng, listener)
		assert_gte(points.size(), 3)
		var mean: Vector2 = Vector2.ZERO
		for p: Vector2i in points:
			mean += Vector2(p) + Vector2(0.5, 0.5)
		mean /= points.size()
		if mean.distance_to(listener) < 0.01:
			continue
		var err: float = absf(rad_to_deg(angle_difference((mean - listener).angle(), (creature_at - listener).angle())))
		total += err
		n += 1
	var mae: float = total / n
	gut.p("tell bearing: mean absolute error %.1f degrees over %d placements" % [mae, n])
	assert_gt(n, 900)
	assert_between(mae, 80.0, 100.0, "uncorrelated with the creature's bearing")


func test_the_cue_says_near_not_where() -> void:
	var s: Scenario = make({"seed": 32, "fixture": W.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(2)
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(12, 10))
	var moth: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var cues: Array[Dictionary] = []
	s.run.creatures.tell_cue.connect(func(slot: int, record: Dictionary) -> void:
		assert_eq(slot, ann.slot)
		cues.append(record))
	var tell: Tell = s.run.creatures.begin_tell(s.run, moth, &"moth_rustle", 10.0)
	s.step(3)
	assert_eq(cues.size(), 1, "the listener within reach gets it once")
	var keys: Array = cues[0].keys()
	keys.sort()
	assert_eq(keys, ["points", "tell"], "no origin, no position, no entity")
	var points: Array[Vector2i] = cues[0]["points"]
	assert_false(points.has(moth.tile(s.run)), "never the creature's tile")
	s.run.creatures.end_tell(s.run, tell)
	var logged: Dictionary = s.run.creatures.log.of_type(&"tell")[0]
	assert_eq(float(Variants.number(logged["reach"])), 10.0, "the log (server-only) keeps the origin and reach")
	assert_true(logged.has("origin"))
	var short: Tell = s.run.creatures.begin_tell(s.run, moth, &"moth_rustle", 6.0)
	assert_false(short.valid, "a reach of 6 tiles or less is refused")
	assert_push_error("not beyond")
