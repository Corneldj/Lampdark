extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04 at base camp: a frenzied Moth that gets in through an open gate covers one emergency lamp
## for 8 s, then ignores all of base camp's emergency light for 60 s, while flames and lit miners
## stay targets.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_inside() -> void:
	var s: Scenario = make({"seed": 83, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(2)
	var m: Moth = A.awake(s, Vector2i(5, 12), true)
	var emergency: int = camp.lights.source
	assert_gte(A.until_state(s, m, &"linger", 200), 0)
	var covers: Array[Dictionary] = s.run.creatures.log.of_type(&"moth_cover")
	assert_eq(covers.size(), 1)
	assert_eq(int(Variants.number(covers[0]["source"])), emergency, "it covers the emergency light")
	var covered_at: int = s.run.tick
	assert_between(A.until_state(s, m, &"search", 400), 158, 161, "for 8 s")
	assert_true(m.awake.perception.searched.has(emergency), "then all base camp's emergency light is searched")
	# A lit miner comes in: a flame is still a target.
	var targets: Array[Dictionary] = []
	s.run.creatures.log.logged.connect(func(e: Dictionary) -> void:
		if e["type"] == &"moth_target":
			targets.append(e))
	var ann: MinerHandle = A.lit_miner(s, "ann", Vector2i(14, 12))
	assert_gte(A.until_state(s, m, &"windup", 400), 0, "it hunts ann's flame")
	for t: Dictionary in targets:
		assert_ne(int(Variants.number(t["source"])), emergency, "never the emergency light again inside the 60 s")
	assert_lt(s.run.tick - covered_at, 1400)
	assert_true(ann.entity_id > 0)
