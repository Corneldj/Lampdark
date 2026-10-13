extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-01 through a run: when a relax begins, chosen hunts end (a wind-up under way finishes
## first), consequences go on, and no new chosen hunt begins unless the apex is on.

const W = preload("res://tests/scenario/creatures/creature_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_relax() -> void:
	var s: Scenario = make({"seed": 41, "fixture": W.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(30, 10))
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(20, 2))
	s.place_stand_in(WorldIds.EntityKind.TAPPER, Vector2i(20, 17))
	s.step(2)
	var cs: CreatureSystem = s.run.creatures
	var moth: KitCreature = cs.creature_of_kind(WorldIds.EntityKind.MOTH)
	var tapper: KitCreature = cs.creature_of_kind(WorldIds.EntityKind.TAPPER)
	var relax: Array[bool] = [false]
	var apex: Array[bool] = [false]
	cs.gate.relax_active = func() -> bool: return relax[0]
	cs.gate.apex_on = func() -> bool: return apex[0]
	var ended: Array[String] = []
	cs.gate.hunt_ended.connect(func(c: Creature, _miner: int, reason: String) -> void: ended.append("%s:%s" % [c.kind_name(), reason]))
	assert_true(cs.gate.request_commit(s.run, moth, ann.entity_id, true))
	assert_true(cs.gate.request_commit(s.run, tapper, bob.entity_id, true))
	var w: CreatureWindUp = cs.begin_wind_up(s.run, tapper, bob.slot, bob.entity_id, 0.5, func(_r: RunState) -> bool: return true)
	s.step(2)
	relax[0] = true
	s.step(1)
	assert_eq(ended, ["moth:relax"] as Array[String], "the Moth's chosen hunt ends at once")
	assert_true(cs.gate.is_hunting(tapper), "the Tapper's wind-up under way finishes first")
	assert_eq(moth.relax_started, 1)
	assert_false(cs.gate.request_commit(s.run, moth, ann.entity_id, true), "no chosen hunt in a relax")
	assert_true(cs.gate.request_commit(s.run, moth, ann.entity_id, false), "a consequence still commits")
	s.step(12)
	assert_ne(w.outcome, CreatureWindUp.Outcome.RUNNING, "the wind-up finished")
	assert_false(cs.gate.is_hunting(tapper), "then its chosen hunt ended")
	assert_true(ended.has("tapper:relax"))
	assert_true(cs.gate.is_hunting(moth), "the consequence hunt goes on")
	cs.gate.stand_down(s.run, moth, "lost them")
	apex[0] = true
	assert_true(cs.gate.request_commit(s.run, moth, ann.entity_id, true), "the apex ignores the relax")
	relax[0] = false
	s.step(1)
	assert_eq(cs.log.of_type(&"hunt_started").size(), 4, "two chosen, one consequence, one in the apex")
