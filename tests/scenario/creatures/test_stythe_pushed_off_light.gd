extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: Ann walks a road toward the Stythe with her lamp lit; it keeps ahead of her light, never
## ending a tick on a tile lit to 0.30 unless the light came to it there, and moving at 3.5 tiles/s.

const W = preload("res://tests/unit/creatures/stythe_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_it_keeps_ahead_of_her_light() -> void:
	var s: Scenario = make({"seed": 1311, "fixture": W.road(70), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(20, 2))
	s.step(1)
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(4, 2), 0.0)
	s.step(1)
	L.lit_in_hand(s, ann)
	ann.at(s.run.tick + 1).move(0.0, InputRecord.Gait.WALK, 300)
	var on_lit: Dictionary = {}
	var max_step: float = 0.0
	var last: Vector2 = st.position(s.run)
	var prev_tile: Vector2i = st.tile(s.run)
	var prev_lit: bool = false
	for _i: int in 300:
		s.step(1)
		var t: Vector2i = st.tile(s.run)
		var lit: bool = not st.unlit(s.run, t)
		if lit:
			# Only on the tile the light came to it on (it may still be leaving it).
			assert_true(t == prev_tile and (prev_lit or not on_lit.has(t)), "stepped onto light at tick %d" % s.run.tick)
			on_lit[t] = true
		max_step = maxf(max_step, st.position(s.run).distance_to(last))
		last = st.position(s.run)
		prev_tile = t
		prev_lit = lit
	gut.p("Ann at %s, the Stythe at %s" % [s.run.registry.get_entity(ann.entity_id).tile(), st.tile(s.run)])
	assert_lte(max_step, Tuning.f(&"stythe.speed") / 20.0 + 1e-4, "never faster than 3.5 tiles/s")
	assert_gt(st.tile(s.run).x, 20, "driven ahead of her")
