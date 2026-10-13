extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-07: feeling a sleeping Moth adds nothing to its stir clock and wakes nothing; feeling a set
## trap springs nothing; feeling emits no Road Graph event at all.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const F = preload("res://tests/unit/vis/feel_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_never() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	s.place_creature(WorldIds.EntityKind.MOTH, a + Vector2i(1, 0))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var trap: int = s.run.registry.create(WorldIds.EntityKind.TRAP, Vector2(a) + Vector2(-0.5, 1.5)).id
	var ann: MinerHandle = s.add_miner("ann", a)
	s.step(2)
	var hunger: int = m.sleep.hunger_at
	var noise_before: int = s.run.noise.event_log.size()
	var states: Array[StringName] = []
	s.on_tick = func(_sc: Scenario) -> void:
		if states.is_empty() or states.back() != m.state.name:
			states.append(m.state.name)
	F.feel(s, ann)
	assert_eq(str(ann.connection.feel.last_feel["caption_key"]), "feel.heap_of_coats", "the sleeping Moth, nearest, as a heap")
	F.feel(s, ann)
	assert_eq(states, [&"asleep"] as Array[StringName], "never stirs, never wakes")
	assert_eq(m.sleep.hunger_at, hunger, "its clock untouched")
	assert_true(s.run.registry.has(trap), "the trap springs nothing")
	assert_null(s.run.holds.caught_in(ann.entity_id))
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UPRIGHT)
	assert_eq(s.run.noise.event_log.size(), noise_before, "silent: no Road Graph event")
