extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-03 (scn_trap_pin_sequence): a man-trap, then a Tapper pin, then the pin broken: the
## signals in order, and the miner ends Caught, Hurt and rock-touched.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_sequence() -> void:
	var s: Scenario = make({"seed": 62, "fixture": FixtureMap.from_ascii(PackedStringArray(["#######", "#a....#", "#######"]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var sm: MinerStateSystem = s.run.miner_state
	var log: Array[String] = []
	sm.state_changed.connect(func(_e: int, _o: int, n: int, cause: String) -> void: log.append("%s:%s" % [MinerTransitions.Life.find_key(n), cause]))
	sm.overlay_changed.connect(func(_e: int, w: StringName, on: bool, cause: String) -> void: log.append("%s %s:%s" % [w, "on" if on else "off", cause]))
	sm.enter_caught(ann.entity_id, &"man_trap", 1)
	s.step(3)
	sm.enter_grabbed(ann.entity_id, &"pin", 77)
	s.step(3)
	sm.end_grab(ann.entity_id, true)
	s.step(3)
	assert_eq(log, ["trap_wound on:man_trap", "CAUGHT:caught:man_trap", "GRABBED:grabbed:pin", "CAUGHT:grab_broken:pin",
		"hurt on:released_from_pin", "rock_touched on:freed_from_pin"])
	var m: MinerStateSystem.Miner = sm.miner(ann.entity_id)
	assert_eq(m.life, MinerTransitions.Life.CAUGHT)
	assert_true(m.overlays.hurt(s.run.tick))
	assert_true(m.overlays.rock_touched(s.run.tick))
