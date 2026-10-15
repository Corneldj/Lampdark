extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-16 with NET-06: at 120 ms round trip, a teammate running across the line is hit where the
## shooter's client showed him, though he has moved on since; no defender rule delays the shot.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hit_where_the_shooter_saw_him() -> void:
	var s: Scenario = make({"seed": 1251, "fixture": R.hall(40)})
	R.lit(s, 40)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	var bob: MinerHandle = R.miner(s, "bob", Vector2i(12, 1), 90.0)
	ann.link(120, 0.0)
	s.step(4)
	R.armed(s, ann)
	R.aim(s, ann, 400)
	s.step(10)
	bob.at(s.run.tick).move(90.0, InputRecord.Gait.WALK, 60)
	var seen: Dictionary = {}
	ann.capture.on_decoded = func(d: FrameDecoder.Decoded) -> void:
		for raw: Variant in d.view.entities.values():
			var e: Dictionary = raw
			seen[d.tick] = e["position"]
	var fired_at: Array[Dictionary] = []
	var fire: Callable = func(sc: Scenario) -> void:
		if not fired_at.is_empty() or seen.is_empty():
			return
		var ticks: Array = seen.keys()
		ticks.sort()
		var latest: int = ticks[ticks.size() - 1]
		var p: Vector2 = seen[latest]
		var me: Vector2 = sc.run.registry.get_entity(ann.entity_id).position
		if absf(p.y - 2.5) > 0.05:
			return
		var deg: float = rad_to_deg((p - me).angle())
		ann.at(sc.run.tick).press(ActionRecord.Kind.TRIGGER, 0, deg)
		fired_at.append({"tick": sc.run.tick, "seen": p})
	s.on_tick = fire
	s.step(60)
	s.on_tick = Callable()
	assert_eq(fired_at.size(), 1, "she fired at him as she saw him cross")
	assert_gt(s.run.revolver.shots.size(), 0)
	var shot: Dictionary = s.run.revolver.shots[0]
	assert_eq(int(Variants.number(shot["hit"])), bob.entity_id, "hit where she saw him")
	# Without the rewind it would have missed: where he stood when the shot was judged.
	var unrewound: Dictionary = s.run.rewind.trace_bodies(Vector2(3.5, 2.5), Vector2.RIGHT, 20.0, float(s.run.tick), ann.entity_id)
	assert_true(unrewound.is_empty() or int(Variants.number(unrewound.get("entity", 0))) != bob.entity_id,
		"judged on the live state, the same aim misses him now")
	var lag: int = int(Variants.number(shot["tick"])) - int(Variants.number(fired_at[0]["tick"]))
	gut.p("the shot landed %d ticks after her press; he had moved on meanwhile" % lag)
	assert_lte(lag, 4, "no defender rule: the shot lands on arrival")
