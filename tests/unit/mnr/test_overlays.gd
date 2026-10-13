extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-03's overlays: Hurt's 1,200 ticks, restarted by a second cause; the single wound slot;
## a cured trap wound leaves Hurt on; nothing cures rock-touched; one signal per change; the
## pin over a trap; the drag over a man-trap; the outcome over the life state.

const Life = MinerTransitions.Life


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hurt_lasts_1200_ticks_and_restarts() -> void:
	var sm: MinerStateSystem = MinerStateSystem.new()
	sm.add_miner(1)
	sm.make_hurt(1, "blast")
	sm.flush(0)
	assert_eq(sm.miner(1).overlays.hurt_until, 1200)
	sm.make_hurt(1, "blackdamp")
	sm.flush(500)
	assert_eq(sm.miner(1).overlays.hurt_until, 1700, "a second cause restarts it")


func test_the_wound_slot_and_the_cured_trap_wound() -> void:
	var s: Scenario = make({"seed": 60, "fixture": FixtureMap.from_ascii(PackedStringArray(["#".repeat(30), "#a" + ".".repeat(27) + "#", "#".repeat(30)]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var sm: MinerStateSystem = s.run.miner_state
	sm.make_hurt(ann.entity_id, "blast")
	sm.add_mark(ann.entity_id, MinerOverlays.TRAP_WOUND)
	s.step(2)
	assert_almost_eq(s.run.movement.modifiers(ann.slot).factor(), 0.8, 1e-9, "Hurt and a trap wound: 0.8, never 0.64")
	sm.cure_mark(ann.entity_id, MinerOverlays.TRAP_WOUND)
	s.step(2)
	assert_true(sm.miner(ann.entity_id).overlays.hurt(s.run.tick), "Hurt runs on under the wound")
	assert_almost_eq(s.run.movement.modifiers(ann.slot).factor(), 0.8, 1e-9)
	s.step(1200)
	assert_almost_eq(s.run.movement.modifiers(ann.slot).factor(), 1.0, 1e-9, "and ends on time")


func test_no_api_cures_rock_touched() -> void:
	var sm: MinerStateSystem = MinerStateSystem.new()
	sm.add_miner(1)
	sm.set_rock_touched(1, 9000)
	sm.flush(0)
	sm.set_rock_touched(1, 10)  # an earlier time never shortens it
	sm.cure_mark(1, &"rock_touched")
	var results: Array = sm.flush(1)
	assert_false(Variants.flag(Variants.array(results[1])[2]), "rock-touched is no mark")
	assert_push_error_count(1)
	assert_eq(sm.miner(1).overlays.rock_touched_until, 9000)
	for method: Dictionary in sm.get_method_list():
		var name: String = method["name"]
		assert_false(name.contains("rock") and (name.contains("cure") or name.contains("clear") or name.contains("remove")), name)


func test_one_signal_per_change_with_its_cause() -> void:
	var sm: MinerStateSystem = MinerStateSystem.new()
	var log: Array[String] = []
	sm.state_changed.connect(func(e: int, o: int, n: int, cause: String) -> void: log.append("state %d %d>%d %s" % [e, o, n, cause]))
	sm.overlay_changed.connect(func(e: int, w: StringName, on: bool, cause: String) -> void: log.append("overlay %d %s %s %s" % [e, w, on, cause]))
	sm.outcome_set.connect(func(e: int, o: int, cause: String) -> void: log.append("outcome %d %d %s" % [e, o, cause]))
	sm.add_miner(1)
	sm.enter_caught(1, &"man_trap", 4)
	sm.flush(1)
	sm.release_caught(1, "teammate")
	sm.flush(2)
	sm.kill(1, "shot")
	sm.flush(3)
	sm.set_outcome(1, MinerTransitions.Outcome.ESCAPED)
	sm.flush(4)
	assert_eq(log, ["overlay 1 trap_wound true man_trap", "state 1 0>1 caught:man_trap", "state 1 1>0 released:teammate",
		"state 1 0>4 shot", "outcome 1 1 cage"])
	assert_eq(sm.describe(1), "Dead, brought home", "the outcome keeps the life state")


func test_a_pin_over_a_trap_and_a_drag_over_a_man_trap() -> void:
	var sm: MinerStateSystem = MinerStateSystem.new()
	sm.add_miner(1)
	sm.enter_caught(1, &"timber_pin", 7)
	sm.flush(1)
	sm.enter_grabbed(1, &"pin", 50)
	sm.flush(2)
	assert_eq(sm.life(1), Life.GRABBED, "a pin over a Caught miner: Grabbed")
	sm.end_grab(1, true)
	sm.flush(3)
	assert_eq(sm.life(1), Life.CAUGHT, "broken: Caught again")
	assert_true(sm.miner(1).overlays.hurt(3), "and Hurt")
	assert_true(sm.miner(1).overlays.rock_touched(3), "and rock-touched")
	sm.add_miner(2)
	sm.enter_caught(2, &"man_trap", 8)
	sm.flush(4)
	sm.cure_mark(2, MinerOverlays.TRAP_WOUND)
	sm.flush(5)
	sm.enter_grabbed(2, &"drag", 51)
	sm.flush(6)
	assert_eq(sm.life(2), Life.GRABBED)
	assert_true(sm.miner(2).holder.is_empty(), "torn out of the trap")
	assert_true(sm.miner(2).overlays.marks.has(MinerOverlays.TRAP_WOUND), "with the trap's wound")
	sm.end_grab(2, false)
	sm.flush(7)
	assert_eq(sm.life(2), Life.UNCONSCIOUS, "a drag run out")


func test_unconscious_in_a_trap_stays_held_and_a_self_revive_hurts() -> void:
	var sm: MinerStateSystem = MinerStateSystem.new()
	sm.add_miner(1)
	sm.enter_caught(1, &"staple_pit", 2)
	sm.flush(1)
	sm.fall_unconscious(1, "blackdamp")
	sm.flush(2)
	assert_false(sm.miner(1).holder.is_empty(), "Caught underneath")
	assert_true((sm.cues(1) & MinerCues.HELD_PIT) != 0)
	sm.revive(1, &"self")
	sm.flush(3)
	assert_eq(sm.life(1), Life.CAUGHT, "comes round still held")
	assert_true(sm.miner(1).overlays.hurt(3))
