extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: the wind-up begins only in reach of a target whose flame is out (the snuff first); the
## grab misses, and the Stythe circles, when a teammate's light of 0.30 is on the target at the end;
## light the victim makes during it (an electric lamp switched on, her shutter opened) never saves her.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(seed_value: int) -> H:
	var s: Scenario = make({"seed": seed_value, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s)
	return h


func test_not_before_her_flame_is_out() -> void:
	var h: H = _world(1411)
	var s: Scenario = h.s
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 1.0, 0, true, LampRules.WICK_NORMAL, Vector2(37.5, 2.5))
	s.step(1)
	s.run.lamps.pick_up(s.run, lamp, h.ann.entity_id)
	s.run.lamps.shutter(s.run, lamp, false)
	assert_true(h.until_state(&"windup", 300))
	var snuffed: int = -1
	for row: Dictionary in h.st.snuff.history:
		snuffed = int(Variants.number(row["tick"]))
	assert_gt(snuffed, 0, "her lamp was snuffed")
	assert_gte(h.st.wind_up.start_tick, snuffed, "the wind-up only after")


func test_a_teammate_light_at_the_end_makes_it_miss() -> void:
	var h: H = _world(1412)
	var s: Scenario = h.s
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(30, 2))
	assert_true(h.until_state(&"windup", 300))
	var tile: Vector2i = s.run.registry.get_entity(h.ann.entity_id).tile()
	s.run.light.grid.add_spot(bob.entity_id, tile, 0.4, 0)  # Bob's light on her, not on it
	s.step(14)
	assert_eq(h.st.wind_up.outcome, CreatureWindUp.Outcome.MISSED, "missed")
	assert_eq(h.st.state.name, &"circle", "and it circles")
	assert_eq(s.run.miner_state.life(h.ann.entity_id), MinerTransitions.Life.UPRIGHT, "she is free")


func test_her_own_light_never_saves_her() -> void:
	for how: String in ["electric", "shutter"]:
		var h: H = _world(1413 if how == "electric" else 1414)
		var s: Scenario = h.s
		var lamp: GauzeLamp = null
		if how == "shutter":
			lamp = s.run.lamps.create(s.run, 1.0, 0, true, LampRules.WICK_NORMAL, Vector2(37.5, 2.5))
			s.step(1)
			s.run.lamps.pick_up(s.run, lamp, h.ann.entity_id)
			s.run.lamps.shutter(s.run, lamp, false)
		assert_true(h.until_state(&"windup", 300))
		var tile: Vector2i = s.run.registry.get_entity(h.ann.entity_id).tile()
		if how == "electric":
			s.run.light.grid.add_spot(h.ann.entity_id, tile, 0.6, 0)  # her own light, switched on now
		else:
			s.run.lamps.shutter(s.run, lamp, true)  # snuffed already: opening it lights nothing
		s.step(18)  # the end, and NET-06's up-to-3-tick wait
		assert_eq(h.st.wind_up.outcome, CreatureWindUp.Outcome.LANDED, "%s: it lands" % how)
		assert_eq(s.run.miner_state.life(h.ann.entity_id), MinerTransitions.Life.GRABBED, "%s: she is taken" % how)
