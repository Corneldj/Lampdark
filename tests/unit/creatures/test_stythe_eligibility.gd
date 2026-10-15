extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: the Stythe senses an unlit miner 10 tiles off by path in ring 1, not 11; 20 in its
## territory; never one standing in 0.30. Eligibility: within reach anywhere; sensed in its territory;
## in its hunting range past the unheard mark or at Pull 50; anywhere at Pull 80. A heard, lit miner
## at Pull 40 in its hunting range is not eligible, and it never closes on them.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


func test_senses_by_path_ring_and_territory() -> void:
	WorldCoords.ring_override = 1
	var s: Scenario = make({"seed": 1201, "fixture": W.road(80), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(1, 2))
	var near: MinerHandle = W.miner(s, "near", Vector2i(11, 2))
	var far: MinerHandle = W.miner(s, "far", Vector2i(12, 2))
	s.step(2)
	assert_true(st.senses.senses(near.entity_id), "10 tiles by path in ring 1")
	assert_false(st.senses.senses(far.entity_id), "not 11")
	W.light(s, Vector2i(11, 2), 0.30)
	s.step(2)
	assert_false(st.senses.senses(near.entity_id), "never a miner standing in 0.30")
	# In its territory (its lair where it stands), it senses 20.
	st.lair = st.tile(s.run)
	st.senses.on_tiles_changed()
	var t20: MinerHandle = W.miner(s, "t20", Vector2i(21, 2))
	var t21: MinerHandle = W.miner(s, "t21", Vector2i(22, 2))
	s.step(2)
	assert_true(st.senses.senses(t20.entity_id), "20 tiles in its territory")
	assert_false(st.senses.senses(t21.entity_id), "not 21")


func test_the_eligibility_table() -> void:
	WorldCoords.ring_override = 1
	var s: Scenario = make({"seed": 1202, "fixture": W.road(200), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(30, 2))
	var reach: MinerHandle = W.miner(s, "reach", Vector2i(31, 2))
	var far: MinerHandle = W.miner(s, "far", Vector2i(190, 2))
	s.step(2)
	assert_eq(StytheEligibility.row(s.run, st, reach.entity_id), "reach", "within 1.5 tiles, anywhere")
	assert_eq(StytheEligibility.row(s.run, st, far.entity_id), "", "far off, no Pull: nobody's")
	W.pull(st, {far.entity_id: 80.0})
	assert_eq(StytheEligibility.row(s.run, st, far.entity_id), "anywhere", "Pull 80: it comes from anywhere")
	# Its territory: the lair 10 tiles behind it.
	st.lair = Vector2i(20, 2)
	st.senses.on_tiles_changed()
	var t: MinerHandle = W.miner(s, "t", Vector2i(36, 2))
	s.step(2)
	assert_eq(StytheEligibility.row(s.run, st, t.entity_id), "territory", "sensed in its territory")
	# Its hunting range (within 150 of the lair), beyond its territory and senses: Pull 50 marks one.
	var r: MinerHandle = W.miner(s, "r", Vector2i(120, 2))
	s.step(2)
	assert_eq(StytheEligibility.row(s.run, st, r.entity_id), "", "unmarked and heard recently")
	W.pull(st, {r.entity_id: 50.0})
	assert_eq(StytheEligibility.row(s.run, st, r.entity_id), "range", "Pull 50 in its hunting range")
	W.pull(st, {})
	# Past the unheard mark (60 s in ring 1) it knows where they are.
	s.step(roundi(61.0 * 20.0))
	assert_eq(StytheEligibility.row(s.run, st, r.entity_id), "range", "past the unheard mark")
	# A heard, lit miner at Pull 40 in its hunting range: not eligible, and it never closes on them.
	var lit: MinerHandle = W.miner(s, "lit", Vector2i(60, 2))
	W.light(s, Vector2i(60, 2), 0.5)
	W.pull(st, {lit.entity_id: 40.0})
	s.step(2)
	s.run.heard.mark_heard(lit.slot, &"voice")
	assert_eq(StytheEligibility.row(s.run, st, lit.entity_id), "", "heard, lit, Pull 40: never")
	var closest: float = INF
	for _i: int in 400:
		s.step(1)
		s.run.heard.mark_heard(lit.slot, &"voice")
		closest = minf(closest, st.position(s.run).distance_to(s.run.registry.get_entity(lit.entity_id).position))
	assert_gt(closest, Tuning.f(&"stythe.reach_tiles"), "it never closed on them")
