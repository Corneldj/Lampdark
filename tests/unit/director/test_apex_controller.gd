extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09: the apex controller. It latches on the engine's first catch, holds through a dry stop and
## a later catch, and clears when the cage leaves, never to begin again; latched, it is the hunt
## gate's apex_on, gives the Tapper the arches' end nearest it and the Stythe the gates' roads within
## stythe.apex_lurk_gate_tiles by path; it is logged; a save brings the latch back and tells the
## creatures again; and FND-08's `apex on|off` forces it.

const A = preload("res://tests/scenario/apex/apex_world.gd")
const D = preload("res://tests/scenario/debug/debug_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int, length: int = 80) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": A.E.T.C.scenario_fixture(), "overrides": A.ON})
	var gate: Gate = A.world(s, length)
	s.step(1)
	return [s, gate]


func _logged(s: Scenario, what: StringName) -> int:
	var n: int = 0
	for e: Dictionary in s.run.creatures.log.entries:
		n += 1 if e["type"] == what else 0
	return n


func test_it_latches_holds_and_clears() -> void:
	var w: Array = _world(9001)
	var s: Scenario = w[0]
	var apex: ApexController = s.run.apex
	var gate: HuntGate = s.run.creatures.gate
	assert_false(apex.active)
	assert_false(Variants.flag(gate.apex_on.call()), "no apex before the catch")
	A.catch_now(s)
	assert_true(apex.active, "the first catch latches it")
	assert_eq(apex.started_tick, s.run.tick)
	assert_true(Variants.flag(gate.apex_on.call()), "the hunt gate's provider")
	var started: int = apex.started_tick
	s.run.engine.stop(s.run, WinderEngine.DRY)
	s.step(20)
	assert_true(apex.active, "a dry engine does not end it")
	A.catch_now(s)
	assert_eq(apex.started_tick, started, "a later catch does not restart it")
	apex.cage_departed(s.run)
	assert_false(apex.active, "the cage leaving clears it")
	assert_false(Variants.flag(gate.apex_on.call()))
	A.catch_now(s)
	assert_false(apex.active, "and it never begins again")
	assert_eq(_logged(s, &"apex_started"), 1)
	assert_eq(_logged(s, &"apex_ended"), 1)


func test_the_arches_end_and_the_gates_roads() -> void:
	var w: Array = _world(9002)
	var s: Scenario = w[0]
	var gate: Gate = w[1]
	var apex: ApexController = s.run.apex
	var t: Tapper = A.tapper(s, A.in_rock(gate, 30))
	var st: StytheCreature = A.stythe(s, A.on_road(gate, 70), A.on_road(gate, 75))
	var before: Variant = t.apex_point.call()
	assert_true(before == null, "nothing before the catch")
	A.catch_now(s)
	assert_eq(apex.arch_ends.size(), 3, "an end to every gate's arches")
	var arch: float = Tuning.f(&"basecamp.arch_length_tiles")
	var end: Vector2 = t.apex_point.call()
	var middle: Vector2 = Vector2(gate.middle()) + Vector2(0.5, 0.5)
	assert_almost_eq(end.distance_to(middle), arch, 1.0, "the arches' end, along its road from the gate")
	# The Stythe's region: the roads by path from the gates, never inside base camp.
	var reach: int = roundi(Tuning.f(&"stythe.apex_lurk_gate_tiles"))
	assert_true(Variants.flag(st.apex_region.call(A.on_road(gate, 20))))
	assert_true(Variants.flag(st.apex_region.call(A.on_road(gate, reach - 2))))
	assert_false(Variants.flag(st.apex_region.call(A.on_road(gate, reach + 5))), "beyond the gates' reach")
	for raw: Variant in apex.region.keys():
		var tile: Vector2i = raw
		assert_true(s.run.mine.native.is_walkable(tile, false))
		assert_false(s.run.base_camp.inside_tiles.has(tile))
		assert_lte(int(Variants.number(apex.region[tile])), reach)
	var near: Variant = st.apex_point.call()
	assert_true(near != null, "the gate mouth nearest it")


func test_a_save_brings_it_back_and_tells_the_creatures_again() -> void:
	var w: Array = _world(9003)
	var s: Scenario = w[0]
	var gate: Gate = w[1]
	var apex: ApexController = s.run.apex
	var m: Moth = A.moth(s, A.on_road(gate, 40))
	s.step(2)
	A.catch_now(s)
	s.step(1)
	assert_eq(m.state.name, &"stirring", "the catch stirs it")
	var saved: Dictionary = apex.save_state()
	var other: ApexController = ApexController.new()
	other.load_state(s.run, saved)
	assert_true(other.active)
	assert_eq(other.started_tick, apex.started_tick)
	# A resume inside the apex: the creatures are told again on the next tick.
	m.fall_asleep(s.run)
	apex.load_state(s.run, saved)
	s.step(2)
	assert_eq(m.state.name, &"stirring", "told again, it stirs to wake")


func test_the_console_forces_it() -> void:
	var w: Array = _world(9004, 40)
	var s: Scenario = w[0]
	if s.run.debug == null:
		pending("the debug server is a dev and QA build's")
		return
	assert_true(Variants.flag(D.run_line(s, "apex on")["ok"]))
	assert_true(s.run.apex.active)
	assert_true(Variants.flag(D.run_line(s, "apex off")["ok"]))
	assert_false(s.run.apex.active)
