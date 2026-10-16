extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02: the apex is outside the cycle (Gameplay §3.6, §10.3). From the engine's catch until the
## cage leaves (LFT-09's provider, stood in for here) the creatures' turn toward base camp and its
## hunts go ahead in a relax; illusions stay blocked; DIR-05's cap still binds.

const D = preload("res://tests/scenario/director/draught_world.gd")
const T = preload("res://tests/scenario/creatures/hunt_world.gd")
const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_hunts_go_ahead_illusions_stay_blocked_and_the_cap_binds() -> void:
	T.ring(1)
	var s: Scenario = make({"seed": 1601, "fixture": T.road(), "director": true})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 5))
	var t: Tapper = T.tapper(s, Vector2i(10, 8))
	D.stand_in(s)
	var gate: HuntGate = s.run.creatures.gate
	gate.apex_on = func() -> bool: return true
	D.force_relax(s, true)
	s.step(3)
	T.talk(s, bob)
	assert_gt(T.until_state(s, t, &"approach", 10), -1, "in the apex a chosen Approach goes ahead in a relax")
	assert_false(s.run.relax.illusions_allowed(), "illusions stay blocked")
	# The cap still binds: with no place left, the next chosen hunt is refused even in the apex.
	var s2: Scenario = make({"seed": 1602, "fixture": T.road(), "director": true})
	var bob2: MinerHandle = s2.add_miner("bob", Vector2i(14, 5))
	var t2: Tapper = T.tapper(s2, Vector2i(10, 8))
	D.stand_in(s2)
	s2.run.creatures.gate.apex_on = func() -> bool: return true
	s2.run.creatures.gate.cap_for = func(_crew: int) -> int: return 0
	D.force_relax(s2, true)
	s2.step(3)
	T.talk(s2, bob2)
	for _i: int in 10:
		s2.step(1)
		assert_ne(t2.state.name, &"approach", "the cap still binds")


func test_the_turn_toward_base_camp_ignores_the_relax() -> void:
	var s: Scenario = make({"seed": 1603, "fixture": H.road(), "overrides": H.W.ON, "director": true})
	var h: H = H.new()
	h.build(s, 60, 20, 95)
	D.stand_in(s)
	var gates: Vector2 = Vector2(10.5, 2.5)
	h.st.apex_point = func() -> Variant: return gates
	s.run.creatures.gate.apex_on = func() -> bool: return true
	D.force_relax(s, true)
	var from: float = h.st.position(s.run).distance_to(gates)
	s.step(200)
	assert_lt(h.st.position(s.run).distance_to(gates), from - 10.0, "it turned toward base camp, relax or not")
