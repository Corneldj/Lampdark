extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04: in a relax a prowling Moth never commits, while a frenzy still hunts; only Hunt through
## Search fill a place under the cap; the frenzy budget drains only in Frenzy without a target, then
## it prowls; a smother lingers 8 s, then searches its memory.

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_cap_places() -> void:
	var s: Scenario = make({"seed": 1, "fixture": A.hall()})
	var m: Moth = A.awake(s, Vector2i(5, 5), false)
	var fills: Array[String] = []
	for raw: Variant in m.states.keys():
		var st: CreatureState = m.states[raw]
		if st.fills_cap_place:
			fills.append(str(st.name))
	fills.sort()
	assert_eq(fills, ["hunt", "last_spot", "linger", "search", "smother", "windup"] as Array[String])


func test_relax_blocks_prowl_not_frenzy() -> void:
	var s: Scenario = make({"seed": 2, "fixture": A.hall()})
	var m: Moth = A.awake(s, Vector2i(5, 10), false)
	s.run.creatures.gate.relax_active = func() -> bool: return true
	s.run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, 0, LbLightGrid.FLAG_FLAME | LbLightGrid.FLAG_UNHELD, 4.0, 1.0, Vector2(15.5, 10.5), 0)
	var committed: Array[bool] = []
	s.run.creatures.gate.hunt_started.connect(func(_c: Creature, _m: int, chosen: bool) -> void: committed.append(chosen))
	s.step(100)
	assert_eq(m.state.name, &"prowl", "in a relax a prowling Moth commits to nothing")
	assert_eq(committed.size(), 0)
	m.enter(s.run, &"frenzy", "test")
	m.awake.frenzy_left = 600
	s.step(3)
	assert_eq(m.state.name, &"hunt", "a frenzy hunts through the relax")
	assert_eq(committed, [false] as Array[bool], "a consequence, not a chosen hunt")


func test_frenzy_budget_then_prowl() -> void:
	var s: Scenario = make({"seed": 3, "fixture": A.hall()})
	var m: Moth = A.awake(s, Vector2i(5, 10), true)
	var budget: int = m.awake.frenzy_left
	assert_eq(budget, roundi(CreatureTables.moth_frenzy_s(0) * 20.0))
	s.step(50)
	assert_eq(m.awake.frenzy_left, budget - 50, "drains in Frenzy without a target")
	m.awake.frenzy_left = 5
	s.step(8)
	assert_eq(m.state.name, &"prowl", "spent: Prowl")


func test_smother_lingers_then_searches() -> void:
	var s: Scenario = make({"seed": 4, "fixture": A.hall()})
	var m: Moth = A.awake(s, Vector2i(5, 10), true)
	var ann: MinerHandle = A.lit_miner(s, "ann", Vector2i(12, 10))
	assert_gte(A.until_state(s, m, &"linger", 400), 0, "smothered")
	assert_eq(A.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	var lingered: int = A.until_state(s, m, &"search", 400)
	assert_between(lingered, 159, 161, "8 s over what it smothered")
