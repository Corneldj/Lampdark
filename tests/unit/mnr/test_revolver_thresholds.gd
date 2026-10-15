extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-16: each creature's retreats need 3, 4, 6, 9, 13, 18, 24 and 31 hits (then on by the same
## rule); 1,200 ticks without a hit reset the partial count; counters are separate per creature.
## Below the threshold a hit flinches; at it the creature retreats (CRT-01).

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_growing_thresholds() -> void:
	var want: Array[int] = [3, 4, 6, 9, 13, 18, 24, 31, 39, 48]
	for n: int in want.size():
		assert_eq(RetreatCounters.needed(n + 1), want[n], "retreat %d" % (n + 1))


func test_counts_reset_and_are_per_creature() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var k: RetreatCounters = RetreatCounters.new()
	var retreats: Array[int] = []
	for i: int in 108:
		run.tick = i * 10
		if k.hit(run, 50):
			retreats.append(i + 1)
	assert_eq(retreats, [3, 7, 13, 22, 35, 53, 77, 108] as Array[int], "its hits so far at each retreat")
	var other: RetreatCounters = RetreatCounters.new()
	run.tick = 0
	assert_false(other.hit(run, 60))
	assert_false(other.hit(run, 61), "another creature counts apart")
	run.tick = 1199
	assert_false(other.hit(run, 60), "two on 60 within 1,200 ticks")
	run.tick = 1199 + 1200
	assert_false(other.hit(run, 60), "after 1,200 ticks quiet the count restarts")
	run.tick += 1
	assert_false(other.hit(run, 60), "only two since the reset")
	run.tick += 1
	assert_true(other.hit(run, 60), "the third retreats it")


func test_a_moth_flinches_then_retreats_at_three() -> void:
	var s: Scenario = make({"seed": 1211, "fixture": R.hall()})
	var moth: int = s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(16, 2))
	assert_ne(moth, 0)
	s.run.creatures.set_frozen(s.run, true)
	R.lit(s)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	s.step(2)
	R.armed(s, ann, 6)
	R.aim(s, ann, 200)
	s.step(3)
	var outcomes: Array[StringName] = []
	for i: int in 3:
		R.trigger(s, ann)
		s.step(12)
		outcomes.append(StringName(str(s.run.revolver.shots[s.run.revolver.shots.size() - 1]["outcome"])))
	assert_eq(outcomes, [&"flinch", &"flinch", &"retreat"] as Array[StringName], "two flinches, then the retreat")
	assert_true(s.run.creatures.creature_of(moth).is_retreating(), "it retreats for 120 s")
