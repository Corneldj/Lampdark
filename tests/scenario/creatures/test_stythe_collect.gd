extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: Collect takes an unlit unconscious miner it senses inside its hunting range after 40 ticks
## of breath and no wind-up, then drags them; never a body lit to 0.30, nor one carried under a
## burning hook lamp; it fills no cap place and a relax does not stop it.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _down(seed_value: int) -> H:
	var s: Scenario = make({"seed": seed_value, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 32, 60)
	h.pulls.clear()
	s.step(1)
	assert_true(s.run.falls.fall_unconscious(s.run, h.ann.entity_id, FallCause.Cause.ROOF_FALL))
	return h


func test_collected_after_40_ticks_no_cap_in_a_relax() -> void:
	var h: H = _down(1431)
	var s: Scenario = h.s
	s.run.creatures.gate.relax_active = func() -> bool: return true
	s.run.creatures.gate.cap_for = func(_c: int) -> int: return 0  # the cap full: Collect fills no place
	assert_true(h.until_state(&"collect", 200), "it comes for the body")
	assert_eq(s.run.creatures.gate.active_count(), 0, "no cap place")
	var close: int = -1
	var grabbed: int = -1
	for _i: int in 200:
		s.step(1)
		if close < 0 and h.st.hunt.collect_until >= 0:
			close = s.run.tick - 1
		if h.st.state.name == &"drag":
			grabbed = s.run.holds.grab_of(h.ann.entity_id).began_tick
			break
	assert_gt(grabbed, 0, "it takes hold, in a relax")
	assert_eq(grabbed - close, 40, "after 40 ticks of breath")
	assert_null(h.st.wind_up, "no wind-up")
	assert_eq(s.run.creatures.gate.active_count(), 0, "the drag after a Collect fills no place either")


func test_never_a_lit_or_carried_body() -> void:
	var h: H = _down(1432)
	var s: Scenario = h.s
	var tile: Vector2i = s.run.registry.get_entity(h.ann.entity_id).tile()
	var spot: int = s.run.light.grid.add_spot(0, tile, 0.3, 0)
	s.step(300)
	assert_ne(h.st.state.name, &"collect", "a body lit to 0.30 is behind a wall")
	assert_eq(s.run.holds.grab_of(h.ann.entity_id), null)
	s.run.light.grid.remove_source(spot)
	# Bob carries her with his lamp hooked and burning: lit, never collected.
	var bob: MinerHandle = H.W.miner(s, "bob", tile + Vector2i(1, 0))
	s.step(1)
	L.lit_in_hand(s, bob)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 45)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, bob.entity_id, h.ann.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(bob.entity_id), "carried, under his hook lamp")
	for _i: int in 200:
		s.step(1)
		assert_eq(s.run.holds.grab_of(h.ann.entity_id), null, "never collected from under a burning hook lamp")
