extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02: a shut gate stops miners, lets no lamp's light through, cuts voice and passes a 14 np
## event at 2 np. Open, it spills base camp white into the road: 0.6 at the doorway, 0.30 or more
## to 3.75 tiles, falling to 0.12 at 6. Its state reaches a client only as geometry it sees; a
## client that neither sees nor holds the gate gets nothing of it.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")

const LISTENER: int = 9001


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_shut_blocks() -> void:
	var s: Scenario = make({"seed": 71, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	var inside: Vector2i = west.middle() - west.outward
	var ann: MinerHandle = s.add_miner("ann", inside)
	s.step(2)
	# Movement: ann walks at the gate for 3 s and stays inside.
	ann.at(s.run.tick).move(fposmod(rad_to_deg(Vector2(west.outward).angle()), 360.0), InputRecord.Gait.WALK, 60)
	var furthest: Array[float] = [INF]
	s.on_tick = func(sc: Scenario) -> void:
		var p: Vector2 = sc.run.registry.get_entity(ann.entity_id).position
		furthest[0] = minf(furthest[0], p.x)
	s.step(70)
	assert_gte(furthest[0], float(inside.x), "no miner passes a shut gate")
	# Light: a lamp held right at the gate lights nothing beyond it.
	var lamp: int = s.run.light.grid.add_point("gauze_lamp", 1, 0, 0, 5.5, 1.0, Vector2(inside) + Vector2(0.5, 0.5), 0)
	s.step(2)
	assert_gt(s.run.light.light_at(inside), 0.6)
	for k: int in range(1, 7):
		for t: Vector2i in west.tiles:
			assert_eq(s.run.light.light_at(t + west.outward * k), 0.0, "nothing beyond the shut gate at %d" % k)
	s.run.light.grid.remove_source(lamp)
	# Voice is cut; a 14 np event reaches the road at 2.
	var road: Vector2i = west.middle() + west.outward
	s.run.road_graph.set_player_listener(LISTENER, road)
	var origin: Array[Vector2i] = [inside]
	assert_eq(_heard(s.run.road_graph.propagate(1, origin, 40.0, RoadGraphService.MODE_VOICE)).size(), 0, "no voice crosses")
	var heard: Array[Dictionary] = _heard(s.run.road_graph.propagate(2, origin, Tuning.f(&"noise.gate_np")))
	assert_eq(heard.size(), 1)
	assert_almost_eq(Variants.number(heard[0]["remaining_np"]), 2.0, 1e-4, "14 np reaches the road at 2")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(1)
	assert_eq(_heard(s.run.road_graph.propagate(3, origin, 40.0, RoadGraphService.MODE_VOICE)).size(), 1, "open: voice crosses")
	s.run.road_graph.remove_listener(LISTENER)


## The test listener's deliveries only (the miners are listeners too).
func _heard(deliveries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in deliveries:
		var d: Dictionary = Variants.dict(raw)
		if int(Variants.number(d["listener"])) == LISTENER:
			out.append(d)
	return out


func test_open_spill() -> void:
	var s: Scenario = make({"seed": 72, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.step(1)
	assert_eq(s.run.light.light_at(west.middle() + west.outward), 0.0, "shut: no spill")
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_true(west.open)
	var length: float = Tuning.f(&"basecamp.gate_spill_tiles")
	for t: Vector2i in west.tiles:
		assert_almost_eq(s.run.light.light_at(t), 0.6, 1e-3, "0.6 at the doorway")
		for k: int in range(1, 8):
			var d: float = k - 0.5
			var v: float = s.run.light.light_at(t + west.outward * k)
			if d <= length:
				assert_almost_eq(v, 0.6 - 0.48 * d / length, 1.1e-3, "linear 0.6 -> 0.12 over 6 tiles (%d)" % k)
			else:
				assert_eq(v, 0.0, "nothing past 6 tiles")
			if d <= 3.75:
				assert_gte(v, 0.30 - 1e-9, "core to 3.75 tiles")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_false(west.open)
	assert_eq(west.spill, 0)
	assert_eq(s.run.light.light_at(west.middle() + west.outward), 0.0, "shut again: no spill")


func test_state_reaches_only_who_sees_it() -> void:
	var s: Scenario = make({"seed": 73, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	var south: Gate = camp.gate_system.gate("south")
	var door: Vector2i = west.middle()
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	var cy: MinerHandle = s.add_miner("cy", door - west.outward)
	var bob: MinerHandle = s.add_miner("bob", south.middle() + south.outward * 20)
	cy.at(s.run.tick).face(fposmod(rad_to_deg(Vector2(west.outward).angle()), 360.0))
	s.step(20)
	var bob_saw: Array[bool] = [false]
	s.on_tick = func(_sc: Scenario) -> void:
		var v: ReceivedView = bob.connection.view
		if v != null:
			for t: Vector2i in west.tiles:
				if v.geometry.has(t):
					bob_saw[0] = true
	var before: PackedByteArray = cy.connection.view.geometry.get(door, PackedByteArray())
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(50)
	assert_true(west.open)
	var after: PackedByteArray = cy.connection.view.geometry.get(door, PackedByteArray())
	assert_false(after.is_empty(), "cy, facing the doorway, gets the open gate as geometry")
	assert_ne(after, before, "the flip reaches the client that sees it")
	assert_false(bob_saw[0], "bob neither sees nor holds the west gate: none of its state reaches him")
