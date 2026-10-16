extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-14: the paraffin can in the free hand (Gameplay §4.3). Its holder walks at most (run held is
## a walk) and every step makes 12 np, every 10 ticks; crouched steps slosh at 12 np too (Proposed).
## The lamp hand keeps its lamp, lit. Set down, the miner runs and steps as before.

const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int) -> Array:
	var road: PackedStringArray = PackedStringArray(["#".repeat(60), "#a" + ".".repeat(57) + "#", "#".repeat(60)])
	var s: Scenario = make({"seed": run_seed, "fixture": FixtureMap.from_ascii(road)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var lamp: GauzeLamp = L.lit_in_hand(s, ann)
	var can: Item = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN, 1, {"fills": 4})
	assert_true(s.run.inventory.give(s.run, ann.entity_id, can), "a can rides in the free hand")
	s.step(2)
	return [s, ann, lamp, can]


func _events(s: Scenario, type: NoiseTypes.Type, source: int, from: int = 0) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == type and e.source_entity == source:
			out.append(e)
	return out


func test_walk_at_most_and_every_step_12_np() -> void:
	var w: Array = _world(1481)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var lamp: GauzeLamp = w[2]
	var can: Item = w[3]
	assert_eq(s.run.inventory.hands_of(ann.entity_id).free_hand, can, "in the free hand, never a slot")
	var from: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 40)
	s.step(44)
	assert_almost_eq(s.run.registry.get_entity(ann.entity_id).position.x - from.x, 40 * Tuning.f(&"movement.walk_speed") / 20.0, 0.01,
		"run held: a walk")
	var steps: Array[NoiseSystem.Event] = _events(s, NoiseTypes.Type.STEP_HEAVY, ann.entity_id)
	assert_eq(steps.size(), 4, "a step every 10 ticks")
	for i: int in steps.size():
		assert_eq(steps[i].level_np, 12.0, "it sloshes: 12 np")
		if i > 0:
			assert_eq(steps[i].tick - steps[i - 1].tick, 10)
	assert_eq(_events(s, NoiseTypes.Type.STEP_RUN, ann.entity_id).size(), 0, "never a running step")
	assert_eq(_events(s, NoiseTypes.Type.STEP_WALK, ann.entity_id).size(), 0, "never a quiet one")
	assert_eq(lamp.place, LampRules.Place.HAND, "the lamp hand keeps its lamp")
	assert_true(lamp.burning())


func test_crouched_steps_slosh_too() -> void:
	var w: Array = _world(1482)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var from: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.CROUCH, 40)
	s.step(44)
	assert_almost_eq(s.run.registry.get_entity(ann.entity_id).position.x - from.x, 40 * Tuning.f(&"movement.crouch_speed") / 20.0, 0.01,
		"crouching still crouches")
	var steps: Array[NoiseSystem.Event] = _events(s, NoiseTypes.Type.STEP_HEAVY, ann.entity_id)
	assert_eq(steps.size(), 4, "a crouched step every 10 ticks")
	assert_eq(steps[0].level_np, 12.0)


func test_set_down_the_miner_runs_again() -> void:
	var w: Array = _world(1483)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	s.run.inventory.hands_of(ann.entity_id).free_hand = null
	s.step(2)
	var from: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 20)
	s.step(24)
	assert_eq(_events(s, NoiseTypes.Type.STEP_RUN, ann.entity_id, from).size(), 2, "running again")
	assert_eq(_events(s, NoiseTypes.Type.STEP_HEAVY, ann.entity_id, from).size(), 0, "no slosh")
