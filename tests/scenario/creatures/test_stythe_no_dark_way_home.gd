extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: with no dark way to the lair, the Stythe holds its victim at the dark tile nearest the lair,
## where light can still break the drag, while the victim's 20 s run on.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_holds_at_the_dark_tile_nearest_home() -> void:
	var s: Scenario = make({"seed": 1441, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 80)
	var lit: Array = []
	for x: int in range(60, 66):
		lit.append(Vector2i(x, 2))
	s.run.light.grid.add_area("test", LbLightGrid.COLOUR_AMBER, 0, 0.5, lit)  # a light across the road home
	assert_true(h.until_state(&"drag", 300))
	var grabbed: int = s.run.holds.grab_of(h.ann.entity_id).began_tick
	s.step(200)
	var at: Vector2i = h.st.tile(s.run)
	assert_eq(at, Vector2i(59, 2), "the dark tile nearest home")
	assert_eq(h.st.state.name, &"drag", "still holding her")
	var fell: Array[int] = []
	s.run.falls.fell.connect(func(r: Dictionary) -> void: fell.append(int(Variants.number(r["tick"]))))
	s.run_until(func(_sv: Variant) -> bool: return not fell.is_empty(), 300)
	assert_eq(fell[0] - grabbed + 1, 400, "the 20 s ran on")
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(50, 2))
	for dx: int in range(-2, 3):
		s.run.light.grid.add_spot(bob.entity_id, at + Vector2i(dx, 0), 0.4, 0)
	s.step(3)
	assert_eq(h.st.state.name, &"flee", "still breakable there")
