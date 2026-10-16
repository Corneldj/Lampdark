extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03's groups (Gameplay §10.5): conscious miners within 6 tiles of each other by path, chained.
## Four in a line with 5-tile gaps are one group (−4); a 7-tile gap splits them; a shut gate between
## two miners 3 tiles apart separates them. A miner beside a body (the fallen, as a carrier carries
## one), beside two Hired Hands, or beside Bess is alone.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _sizes(s: Scenario, ids: Array[int]) -> Array[int]:
	s.step(Pull.GROUP_EVERY + 1)
	var out: Array[int] = []
	for e: int in ids:
		out.append(int(Variants.number(s.run.pull.groups.get(e, 0))))
	return out


func _line(seed_value: int, xs: Array[int]) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": D.hall(), "director": true, "slots": 8})
	var ids: Array[int] = []
	for i: int in xs.size():
		ids.append(s.add_miner("m%d" % i, Vector2i(xs[i], 1)).entity_id)
	D.stand_in(s)
	return [s, ids]


func test_a_line_with_5_tile_gaps_is_one_group_at_minus_4() -> void:
	var w: Array = _line(2101, [1, 6, 11, 16] as Array[int])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	assert_eq(_sizes(s, ids), [4, 4, 4, 4] as Array[int], "chained into one group of four")
	s.run.pull.ring_of = func(_m: int) -> int: return 2
	for e: int in ids:
		s.run.pull.set_value(e, 50.0)
	s.step(roundi(60.0 * Tuning.f(&"net.tick_hz")))
	assert_almost_eq(s.run.pull.value_of(ids[3]), 46.0, 0.01, "−4 a minute")


func test_a_7_tile_gap_splits_them() -> void:
	var w: Array = _line(2102, [1, 6, 11, 18] as Array[int])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	assert_eq(_sizes(s, ids), [3, 3, 3, 1] as Array[int], "the fourth, 7 tiles off by path, is alone")


func test_a_shut_gate_between_two_miners_3_tiles_apart_separates_them() -> void:
	var map: FixtureMap = FixtureMap.from_ascii(PackedStringArray(["##########", "#a..G..b.#", "##########"]))
	var s: Scenario = make({"seed": 2103, "fixture": map, "director": true})
	var ann: int = s.add_miner("ann", Vector2i(2, 1)).entity_id
	var ben: int = s.add_miner("ben", Vector2i(5, 1)).entity_id
	D.stand_in(s)
	assert_eq(_sizes(s, [ann, ben] as Array[int]), [1, 1] as Array[int], "a shut gate is a wall")
	assert_true(s.set_gate(1, true))
	assert_eq(_sizes(s, [ann, ben] as Array[int]), [2, 2] as Array[int], "open, they are a pair")


func test_the_fallen_hands_and_bess_are_no_company() -> void:
	var w: Array = _line(2104, [1, 2, 20, 21, 22, 38] as Array[int])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	# ids[0] beside a body (ids[1] fallen); ids[2] beside two Hands (ids[3], ids[4]); ids[5] beside Bess.
	s.run.miner_state.fall_unconscious(ids[1], "test")
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ids[3] or e == ids[4]
	s.run.registry.create(WorldIds.EntityKind.BESS, Vector2(39.5, 1.5))
	var sizes: Array[int] = _sizes(s, [ids[0], ids[2], ids[5]] as Array[int])
	assert_eq(sizes, [1, 1, 1] as Array[int], "beside a body, two Hands or Bess: alone")
	assert_eq(s.run.pull.value_of(ids[1]), 0.0, "the fallen hold no Pull")
	assert_false(s.run.pull.records.has(ids[3]), "nor do Hands")
