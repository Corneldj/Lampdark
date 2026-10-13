extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-04 with VIS-03 and NET-04: an item is a small thing. A spanner on a tile lit to 0.25 is
## never sent, not even as a fringe token; at 0.30 it arrives with identity.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _records_near(view: ReceivedView, at: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in view.entities.values():
		var e: Dictionary = Variants.dict(raw)
		var p: Vector2 = e["position"]
		if p.distance_to(at) < 0.1:
			out.append(e)
	return out


func test_spanner_at_025_and_030() -> void:
	var s: Scenario = make({"seed": 31, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var tile: Vector2i = a + Vector2i(3, 0)
	W.put(s, ItemKinds.Kind.SPANNER, tile)
	var at: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
	var dim: int = s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, 0.25, [tile])
	ann.at(s.run.tick).face(0.0)
	var ever: Array[int] = [0]
	s.on_tick = func(_sc: Scenario) -> void:
		if ann.connection.view != null:
			ever[0] += _records_near(ann.connection.view, at).size()
	s.step(20)
	assert_eq(ever[0], 0, "at 0.25 the spanner is never sent, not even as a token")
	s.on_tick = Callable()
	s.run.light.grid.remove_source(dim)
	s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, 0.30, [tile])
	s.step(10)
	var got: Array[Dictionary] = _records_near(ann.connection.view, at)
	assert_eq(got.size(), 1, "at 0.30 it arrives")
	assert_eq(int(Variants.number(got[0]["level"])), 2, "with identity")
	assert_eq(int(Variants.number(got[0]["size_or_kind"])), SeenKind.Kind.ITEM)


func test_outside_the_cone_is_never_sent() -> void:
	var s: Scenario = make({"seed": 32, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a + Vector2i(3, 0))
	var tile: Vector2i = a
	W.put(s, ItemKinds.Kind.SPANNER, tile)
	var at: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
	ann.at(s.run.tick).face(0.0)
	var ever: Array[int] = [0]
	s.on_tick = func(_sc: Scenario) -> void:
		if ann.connection.view != null:
			ever[0] += _records_near(ann.connection.view, at).size()
	s.step(20)
	assert_eq(ever[0], 0, "lit at 0.6 but behind her: never sent")
	s.on_tick = Callable()
	ann.at(s.run.tick).face(180.0)
	s.step(10)
	assert_eq(_records_near(ann.connection.view, at).size(), 1, "turned to face it, she sees it")
