extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: a teammate's light of 0.30 on the dragging Stythe, or a flare lighting it, makes it drop
## the victim, flee 10 tiles and circle for 600 ticks; a Hired Hand's light never does. Freed before
## 400 ticks the victim stands Upright and Hurt; after, they lie unconscious where dropped.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann grabbed and dragged; then `light` (owner, or -1 for a flare) put on the Stythe's tile after
## `wait` ticks of drag. Returns [h, dropped at].
func _break(seed_value: int, wait: int, owner_kind: String) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s)
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(10, 2))
	if owner_kind == "hand":
		s.run.crew.is_hand_driven = func(e: int) -> bool: return e == bob.entity_id
	assert_true(h.until_state(&"drag", 300), "dragging")
	s.step(wait)
	var at: Vector2i = h.st.tile(s.run)
	if owner_kind == "flare":
		var flare: Item = s.run.inventory.world.make(ItemKinds.Kind.FLARE, 1, {"lit": true, "burn_ticks": 160})
		s.run.inventory.world.put(s.run, flare, Vector2(at) + Vector2(2.5, 0.5))
	else:
		for dx: int in range(-3, 4):
			s.run.light.grid.add_spot(bob.entity_id, at + Vector2i(dx, 0), 0.4, 0)
	s.step(3)
	return [h, at]


func test_a_teammate_light_breaks_it() -> void:
	var r: Array = _break(1421, 60, "teammate")
	var h: H = r[0]
	var s: Scenario = h.s
	assert_eq(h.st.state.name, &"flee", "it flees")
	assert_eq(h.st.drag.victim, 0, "the victim dropped")
	assert_eq(s.run.miner_state.life(h.ann.entity_id), MinerTransitions.Life.UPRIGHT, "freed before 400 ticks: Upright")
	assert_true(s.run.miner_state.miner(h.ann.entity_id).overlays.hurt(s.run.tick), "and Hurt")
	var light: Vector2i = r[1]
	assert_true(h.until_state(&"circle", 200), "then it circles")
	assert_gte(Vector2(h.st.tile(s.run)).distance_to(Vector2(light)), 9.0, "10 tiles from the light")
	var began: int = s.run.tick
	assert_true(h.until_state(&"check", 700))
	assert_eq(s.run.tick - began, 600, "for 600 ticks")


func test_a_flare_breaks_it() -> void:
	var h: H = _break(1422, 60, "flare")[0]
	assert_eq(h.st.state.name, &"flee", "a flare drives it off")
	assert_eq(h.st.drag.victim, 0)


func test_a_hands_light_never_does() -> void:
	var h: H = _break(1423, 60, "hand")[0]
	h.s.step(20)
	assert_eq(h.st.state.name, &"drag", "the Hand's light: the drag goes on")
	assert_eq(h.st.drag.victim, h.ann.entity_id)


func test_after_400_ticks_she_lies_where_dropped() -> void:
	var r: Array = _break(1424, 420, "teammate")
	var h: H = r[0]
	var s: Scenario = h.s
	assert_eq(h.st.drag.victim, 0, "dropped")
	assert_eq(s.run.miner_state.life(h.ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "unconscious")
	var at: Vector2 = s.run.registry.get_entity(h.ann.entity_id).position
	s.step(40)
	assert_eq(s.run.registry.get_entity(h.ann.entity_id).position, at, "where she was dropped")
