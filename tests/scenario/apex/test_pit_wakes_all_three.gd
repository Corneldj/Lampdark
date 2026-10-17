extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09 (Gameplay §3.6, §7.2-§7.4): two miners start the engine and the pit wakes. The Moth, asleep
## 200 tiles down the road, plays its 1.5 s stir tell from the catch tick, wakes into Prowl and drifts
## toward base camp; the Tapper comes to the rock beyond the brick arches and never enters brick; the
## Stythe leaves its lair and lurks only on dark road tiles within 40 tiles of a gate by path. Nothing
## of it reaches a client but what its miner perceives (NET-08's audit).

const A = preload("res://tests/scenario/apex/apex_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_engine_catches_and_the_pit_wakes() -> void:
	var s: Scenario = make({"seed": 9101, "fixture": A.E.T.C.scenario_fixture(), "overrides": A.ON})
	var gate: Gate = A.world(s, 230)
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var m: Moth = A.moth(s, A.on_road(gate, 200))
	var t: Tapper = A.tapper(s, A.in_rock(gate, 60, 5))
	var lair: Vector2i = A.on_road(gate, 80) + Vector2i(gate.outward.y, gate.outward.x) * 7
	var st: StytheCreature = A.stythe(s, lair, lair)
	s.step(5)
	assert_true(m.is_sleeping(), "the Moth asleep, 200 tiles out")
	var caught: int = A.start_engine(s)
	var apex: ApexController = s.run.apex
	assert_true(apex.active, "the catch woke the pit")
	assert_eq(apex.started_tick, caught)
	# The Moth: its stir tell from the catch tick, then Prowl toward base camp.
	assert_not_null(m.stir_tell)
	assert_eq(m.stir_tell.tell_kind, &"moth_stir")
	assert_eq(m.stir_tell.start_tick, caught, "the stir begins on the catch tick")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return m.state.name == &"prowl", 60), "awake, into Prowl")
	assert_eq(m.rose_for, "engine")
	var camp: Vector2 = Vector2(gate.middle())
	var moth_from: float = m.position(s.run).distance_to(camp)
	var lair_at: Vector2 = Vector2(lair) + Vector2(0.5, 0.5)
	var tapper_end: Vector2 = t.apex_point.call()
	var brick: int = WorldIds.TileMaterial.BRICK
	var in_brick: int = 0
	var lurked: int = 0
	var lurk_ok: bool = true
	for _i: int in 1600:
		s.step(1)
		if A.tile_material(s, t.tile(s.run)) == brick:
			in_brick += 1
		if st.state.name == &"lurk" and st.lurk_spot.x != 2147483647 and st.tile(s.run) == st.lurk_spot:
			lurked += 1
			lurk_ok = lurk_ok and apex.region.has(st.tile(s.run)) and st.unlit(s.run, st.tile(s.run))
	assert_lt(m.position(s.run).distance_to(camp), moth_from - 20.0, "the Moth drifted toward base camp")
	assert_eq(in_brick, 0, "the Tapper never in brick")
	assert_lt(t.position(s.run).distance_to(tapper_end), 14.0, "the Tapper at the rock beyond the arches")
	assert_gt(st.position(s.run).distance_to(lair_at), 20.0, "the Stythe left its lair")
	assert_gt(lurked, 0, "and lurked")
	assert_true(lurk_ok, "only on dark road tiles within 40 tiles of a gate by path")
	assert_eq(audit.violation_count, 0, "nothing of the apex in any client's stream")
