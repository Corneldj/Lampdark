extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01: sealed only with all three gates shut; sealed_changed, entered and left fire on the
## tick of the change; the crew census leaves sealed-in miners out.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_sealed_and_signals() -> void:
	var s: Scenario = make({"seed": 1, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var deck: Rect2i = Basecamp.deck_rect(C.SEED, 0)
	var ann: MinerHandle = s.add_miner("ann", deck.position)
	s.step(1)
	assert_true(camp.is_sealed(), "LFT-02 shuts every gate at run start")
	C.shut_all(s, false)
	s.step(1)
	assert_false(camp.is_sealed(), "the gates are open")
	assert_true(camp.is_inside(ann.entity_id))
	var flips: Array[Array] = []
	camp.sealed_changed.connect(func(on: bool) -> void: flips.append([s.run.tick, on]))
	var gates: Array[Dictionary] = Basecamp.gate_specs(C.SEED, 0)
	s.run.mine.native.set_barrier(Vector2i.ZERO, int(Variants.number(gates[0]["barrier"])), false)
	s.run.mine.native.set_barrier(Vector2i.ZERO, int(Variants.number(gates[1]["barrier"])), false)
	s.step(2)
	assert_false(camp.is_sealed(), "two of three shut: not sealed")
	var at: int = s.run.tick
	s.run.mine.native.set_barrier(Vector2i.ZERO, int(Variants.number(gates[2]["barrier"])), false)
	s.step(1)
	assert_true(camp.is_sealed(), "all three shut")
	assert_eq(flips, [[at, true]], "sealed_changed on the tick that took the change (the gate shut between ticks)")
	s.step(2)
	assert_eq(s.run.crew.count, 0, "a miner sealed inside leaves the crew count")
	s.run.mine.native.set_barrier(Vector2i.ZERO, int(Variants.number(gates[1]["barrier"])), true)
	s.step(1)
	assert_false(camp.is_sealed())
	s.step(1)
	assert_eq(s.run.crew.count, 1)


func test_entered_and_left() -> void:
	var s: Scenario = make({"seed": 2, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	C.shut_all(s, false)
	var g: Dictionary = Basecamp.gate_specs(C.SEED, 0)[0]
	var outward: Vector2i = g["outward"]
	var tiles: Array = g["tiles"]
	var mid: Vector2i = tiles[1]
	var ann: MinerHandle = s.add_miner("ann", mid + outward * 3)
	var events: Array[Array] = []
	camp.entered.connect(func(id: int) -> void: events.append(["entered", id, s.run.tick]))
	camp.left.connect(func(id: int) -> void: events.append(["left", id, s.run.tick]))
	s.step(2)
	assert_false(camp.is_inside(ann.entity_id), "on the arch: road, not base camp")
	ann.at(s.run.tick).move(fposmod(rad_to_deg(Vector2(-outward).angle()), 360.0), InputRecord.Gait.WALK, 40)
	var first_inside: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var p: Vector2 = sc.run.registry.get_entity(ann.entity_id).position
		if first_inside[0] < 0 and Basecamp.is_inside_base_camp(C.SEED, Vector2i(floori(p.x), floori(p.y)), 0):
			first_inside[0] = sc.run.tick
	s.step(40)
	assert_eq(events.size(), 1)
	assert_eq(str(events[0][0]), "entered")
	assert_lte(int(Variants.number(events[0][2])) - first_inside[0], 1, "entered on the tick she crossed in")
	ann.at(s.run.tick).move(fposmod(rad_to_deg(Vector2(outward).angle()), 360.0), InputRecord.Gait.WALK, 40)
	s.step(40)
	assert_eq(events.size(), 2)
	assert_eq(str(events[1][0]), "left")
