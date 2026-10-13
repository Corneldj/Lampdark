extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02 with CRT-04: an awake Moth 20 tiles down the road commits to an open gate's spill. With the
## engine running (LFT-09 stubbed: the apex is on), it prowls toward base camp and hunts the spill
## even during a relax.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(2)
	assert_true(west.open)
	return [s, camp, west]


func test_commits_to_the_spill() -> void:
	var parts: Array = _setup(84)
	var s: Scenario = parts[0]
	var west: Gate = parts[2]
	var m: Moth = A.awake(s, west.middle() + west.outward * 20, false)
	var committed: Array[Dictionary] = []
	s.run.creatures.log.logged.connect(func(e: Dictionary) -> void:
		if e["type"] == &"moth_target":
			committed.append(e))
	s.step(10)
	assert_eq(m.state.name, &"hunt", "it commits")
	assert_true(int(Variants.number(committed[0]["source"])) in [west.spill, west.doorway_light], "to the gate's light")
	assert_gte(A.until_state(s, m, &"linger", 400), 0, "and covers it: a light it cannot take")


func test_engine_prowl_in_a_relax() -> void:
	var parts: Array = _setup(85)
	var s: Scenario = parts[0]
	var west: Gate = parts[2]
	s.run.creatures.gate.relax_active = func() -> bool: return true
	s.run.creatures.gate.apex_on = func() -> bool: return true
	# At the foot of the road cell's side branch: loaded, and out of sight of the spill.
	var branch_foot: Vector2i = west.tiles[0] + west.outward * 7 + Vector2i(0, 6)
	assert_true(s.run.mine.native.is_walkable(branch_foot, false))
	s.place_creature(WorldIds.EntityKind.MOTH, branch_foot)
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var start: float = m.position(s.run).distance_to(Vector2(west.middle()))
	assert_true(m.wake(s.run, MothSleep.Cause.ENGINE, Vector2(west.middle())))
	assert_gte(A.until_state(s, m, &"prowl", 100), 0, "the engine wakes it to Prowl")
	assert_eq(m.rose_for, "engine")
	s.step(2)
	assert_eq(m.state.name, &"prowl", "the spill is out of its sight here")
	assert_gte(A.until_state(s, m, &"hunt", 600), 0, "it hunts the spill though a relax is on")
	assert_lt(m.position(s.run).distance_to(Vector2(west.middle())), start, "having prowled toward base camp")
	assert_true(int(Variants.number(m.awake.target["source"])) in [west.spill, west.doorway_light])
