extends "res://tests/scenario/kit/scenario_test.gd"
## FND-08 (Gameplay §7.1, §A.4): spawn places the run's single instance, moving it if it exists;
## nothing creates a second, `creatures off` and `on` included.

const D = preload("res://tests/scenario/debug/debug_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_spawn_moves_the_one_moth() -> void:
	var s: Scenario = make({"seed": 21, "fixture": D.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(3, 2))
	s.step(2)
	assert_true(Variants.flag(D.run_line(s, "spawn moth 25 7")["ok"]))
	var moth: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var first: int = moth.entity_id
	var r: Dictionary = D.run_line(s, "spawn moth here", ann.slot)
	assert_true(Variants.flag(r["ok"]), str(r["text"]))
	assert_eq(s.run.creatures.count_of(WorldIds.EntityKind.MOTH), 1, "exactly one Moth")
	assert_eq(s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH).entity_id, first, "the same Moth, moved")
	assert_eq(Vector2i(moth.position(s.run).floor()), Vector2i(3, 2), "to the issuer's tile")
	var states: Array = moth.states.keys()
	var to_state: String = str(states[states.size() - 1])
	assert_true(Variants.flag(D.run_line(s, "spawn moth 20 1 %s" % to_state)["ok"]))
	assert_eq(str(moth.state.name), to_state, "in the state asked for")
	assert_false(Variants.flag(D.run_line(s, "spawn moth 20 1 no_such_state")["ok"]))


func test_creatures_off_and_on_never_make_a_second() -> void:
	var s: Scenario = make({"seed": 22, "fixture": D.hall()})
	s.add_miner("ann", Vector2i(3, 2))
	s.step(2)
	assert_true(Variants.flag(D.run_line(s, "spawn tapper 25 7")["ok"]))
	var t: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	var old_entity: int = t.entity_id
	assert_true(Variants.flag(D.run_line(s, "creatures off tapper")["ok"]))
	assert_null(s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER), "out of the simulation")
	assert_false(s.run.registry.has(old_entity), "and out of every perception: no entity")
	assert_eq(s.run.creatures.count_of(WorldIds.EntityKind.TAPPER), 1, "still the run's one Tapper")
	s.step(20)
	assert_true(Variants.flag(D.run_line(s, "spawn tapper 5 7")["ok"]), "spawn while off brings it back, moved")
	assert_eq(s.run.creatures.count_of(WorldIds.EntityKind.TAPPER), 1)
	assert_true(Variants.flag(D.run_line(s, "creatures off")["ok"]))
	assert_true(Variants.flag(D.run_line(s, "creatures on")["ok"]))
	var back: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	assert_eq(back, t, "the same creature object")
	assert_eq(Vector2i(back.position(s.run).floor()), Vector2i(5, 7), "where it was")
	assert_eq(s.run.creatures.count_of(WorldIds.EntityKind.TAPPER), 1)
	var second: Tapper = Tapper.new()
	assert_eq(s.run.creatures.place_now(s.run, second, Vector2i(15, 7)), ERR_ALREADY_EXISTS, "a second is refused")
