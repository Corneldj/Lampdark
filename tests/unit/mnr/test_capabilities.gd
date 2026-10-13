extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-03's capabilities match the §4.2 table, and reach MNR-01's movement.

const Life = MinerTransitions.Life


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_table() -> void:
	var sm: MinerStateSystem = MinerStateSystem.new()
	var want: Dictionary = {
		Life.UPRIGHT: [true, true, true, true, true, "yes", true],
		Life.CAUGHT: [false, true, true, true, true, "reach", true],
		Life.GRABBED: [false, true, true, false, false, "self_rescue", false],
		Life.UNCONSCIOUS: [false, false, false, false, false, "no", false],
		Life.DEAD: [false, false, false, false, false, "no", false],
	}
	var entity: int = 1
	for state: Variant in want.keys():
		sm.add_miner(entity)
		match int(Variants.number(state)):
			Life.CAUGHT: sm.enter_caught(entity, &"man_trap", 1)
			Life.GRABBED: sm.enter_grabbed(entity, &"pin", 2)
			Life.UNCONSCIOUS: sm.fall_unconscious(entity, "smother")
			Life.DEAD: sm.kill(entity, "shot")
		sm.flush(entity)
		var caps: Dictionary = sm.capabilities(entity)
		var got: Array = [caps["move"], caps["turn"], caps["voice"], caps["lamp"], caps["belt"], caps["interact"], caps["signals"]]
		var expected: Array = want[state]
		assert_eq(got, expected, str(Life.find_key(int(Variants.number(state)))))
		entity += 1
	sm.set_crawl_window(4, true)
	assert_true(Variants.flag(sm.capabilities(4)["move"]), "the coming-round window opens the crawl")


func test_caught_turns_but_does_not_move() -> void:
	var s: Scenario = make({"seed": 61, "fixture": FixtureMap.from_ascii(PackedStringArray(["#".repeat(20), "#a" + ".".repeat(17) + "#", "#".repeat(20)]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.run.miner_state.enter_caught(ann.entity_id, &"man_trap", 1)
	s.step(2)
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	ann.at(2).move(0.0, InputRecord.Gait.RUN, 20).face(90.0)
	s.step(25)
	assert_eq(s.run.registry.get_entity(ann.entity_id).position, at, "held in place")
	assert_eq(s.run.movement.facing_of(ann.slot), 16384, "but turning")
	s.run.miner_state.fall_unconscious(ann.entity_id, "blast")
	s.step(2)
	ann.at(29).face(270.0)
	s.step(5)
	assert_eq(s.run.movement.facing_of(ann.slot), 16384, "the unconscious do not turn")
