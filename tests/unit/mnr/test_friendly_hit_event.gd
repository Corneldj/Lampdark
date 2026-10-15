extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-16: every miner or Hand hit emits one `friendly_hit`. With RSC-05's and MOD-11's stubs:
## among friends the miner is dead, in public unconscious with the shooter named, and a second
## friendly hit by the same shooter asks for an ejection. A dead body on the line stops the shot
## with no effect; Bess hit emits `bess_hit`.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int, mode: ServerConfig.Mode) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": R.hall(), "mode": mode})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	var bob: MinerHandle = R.miner(s, "bob", Vector2i(10, 2), 180.0)
	s.step(2)
	R.armed(s, ann)
	R.aim(s, ann)
	s.step(3)
	return [s, ann, bob]


func test_friends_dead_with_one_event() -> void:
	var w: Array = _world(1231, ServerConfig.Mode.FRIENDS)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var events: Array[Array] = []
	s.run.revolver.friendly_hit.connect(func(v: int, sh: int, t: int) -> void: events.append([v, sh, t]))
	R.trigger(s, ann)
	s.step(8)
	assert_eq(events.size(), 1, "one friendly_hit")
	var victim: int = events[0][0]
	var shooter: int = events[0][1]
	assert_eq(victim, bob.entity_id)
	assert_eq(shooter, ann.entity_id)
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.DEAD, "among friends: dead")
	var bodies_before: int = s.run.revolver.friendly_hits.size()
	R.trigger(s, ann, 0.0, s.run.tick + 12)
	s.step(20)
	var last: Dictionary = s.run.revolver.shots[s.run.revolver.shots.size() - 1]
	assert_eq(StringName(str(last["outcome"])), &"stopped_by_the_dead", "a dead body stops the shot, with no effect")
	assert_eq(s.run.revolver.friendly_hits.size(), bodies_before)


func test_public_unconscious_and_a_second_hit_ejects() -> void:
	var w: Array = _world(1232, ServerConfig.Mode.PUBLIC)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	R.trigger(s, ann)
	s.step(8)
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.UNCONSCIOUS, "in public: unconscious")
	var fell: Dictionary = s.run.falls.journal[s.run.falls.journal.size() - 1]
	assert_eq(int(Variants.number(fell["cause"])), FallCause.Cause.FRIENDLY_HIT, "a friendly hit, the shooter named")
	assert_eq(s.run.revolver.ejections.size(), 0)
	var cara: MinerHandle = R.miner(s, "cara", Vector2i(8, 2), 180.0)
	s.step(14)
	R.trigger(s, ann)
	s.step(8)
	assert_eq(s.run.revolver.friendly_hits.size(), 2)
	assert_eq(s.run.revolver.ejections.size(), 1, "a second friendly hit ejects (MOD-11)")
	assert_eq(int(Variants.number(s.run.revolver.ejections[0]["shooter"])), ann.entity_id)
	assert_ne(cara.entity_id, 0)


func test_bess_hit() -> void:
	var s: Scenario = make({"seed": 1233, "fixture": R.hall()})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	s.run.registry.create(WorldIds.EntityKind.BESS, Vector2(9.5, 2.5))
	s.step(2)
	R.armed(s, ann)
	R.aim(s, ann)
	s.step(3)
	var bess: Array[int] = []
	s.run.revolver.bess_hit.connect(func(sh: int, _t: int) -> void: bess.append(sh))
	R.trigger(s, ann)
	s.step(8)
	assert_eq(bess, [ann.entity_id] as Array[int], "bess_hit (MOD-07)")
