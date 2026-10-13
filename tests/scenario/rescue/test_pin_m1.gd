extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03 for M1 with a stand-in Tapper strike (CRT-09 replaces it): the pin holds its victim for
## tapper.pin_s, then they fall at the wall; in a second run a teammate's silent pull frees the
## victim, Hurt and rock-touched; the hunt stands down when the grab ends.

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _pinned(s: Scenario) -> Array:
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.add_miner("bob", s.fixture.spot("c"))
	s.place_stand_in(WorldIds.EntityKind.TAPPER, Vector2i(2, 2))
	var tapper: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	s.step(1)
	assert_true(s.run.creatures.gate.request_commit(s.run, tapper, ann.entity_id, true))
	var limit: int = roundi(Tuning.f(&"tapper.pin_s") * Tuning.f(&"net.tick_hz"))
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, tapper.entity_id, limit)
	tapper.grabbing = ann.entity_id
	# The stand-in Tapper ends the pin when it runs out, as CRT-09 does.
	s.run.holds.grab_timed_out.connect(func(g: int) -> void: s.run.holds.end_grab(s.run, g, GrabHold.Outcome.TIMED_OUT))
	return [ann, tapper, id, limit]


func test_pin_runs_out() -> void:
	var s: Scenario = make({"seed": 12, "fixture": H.hall()})
	var r: Array = _pinned(s)
	var ann: MinerHandle = r[0]
	var tapper: Creature = r[1]
	var limit: int = r[3]
	assert_eq(limit, 500, "25 s")
	s.step(limit - 2)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.GRABBED)
	s.step(3)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "fallen at the wall's foot")
	assert_false(s.run.creatures.gate.is_hunting(tapper), "the hunt stood down with the grab")


func test_silent_pull_frees() -> void:
	var s: Scenario = make({"seed": 13, "fixture": H.hall()})
	var r: Array = _pinned(s)
	var ann: MinerHandle = r[0]
	var id: int = r[2]
	s.step(100)
	assert_true(s.run.holds.end_grab(s.run, id, GrabHold.Outcome.BROKEN), "a teammate's silent pull")
	s.step(1)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT)
	var m: MinerStateSystem.Miner = s.run.miner_state.miner(ann.entity_id)
	assert_gt(m.overlays.hurt_until, s.run.tick, "Hurt")
	assert_true(m.overlays.rock_touched(s.run.tick), "and rock-touched")
