extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02: a lever action takes basecamp.gate_lever_s (30 ticks); the gate flips on its last tick
## with exactly one 14 np clang at the gateway; released early, nothing changes; a hold kept after
## the flip starts no second action; every gate is shut at run start.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	s.step(2)
	return [s, camp, ann]


func test_shut_at_run_start() -> void:
	var parts: Array = _setup(11)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	assert_eq(camp.gate_system.gates.size(), 3, "three gates; the blind side has none")
	for g: Gate in camp.gate_system.gates:
		assert_false(g.open, "%s shut at run start" % g.side)
		for t: Vector2i in g.tiles:
			assert_eq(s.run.mine.native.effective_material(t), WorldIds.TileMaterial.STEEL)
	assert_true(camp.is_sealed())
	assert_eq(C.clangs(s).size(), 0, "installing makes no sound")


func test_flip_on_the_last_tick() -> void:
	var parts: Array = _setup(12)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var ann: MinerHandle = parts[2]
	var west: Gate = camp.gate_system.gate("west")
	assert_eq(roundi(Tuning.f(&"basecamp.gate_lever_s") * 20.0), 30)
	var started: Array[int] = [-1]
	var flips: Array[Array] = []
	camp.gate_system.flipped.connect(func(side: String, open: bool) -> void: flips.append([side, open, s.run.tick]))
	s.on_tick = func(_sc: Scenario) -> void:
		var a: Gate.LeverAction = west.actions.get(ann.entity_id, null)
		if a != null and started[0] < 0:
			started[0] = a.started_tick
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	s.step(100)
	assert_eq(flips.size(), 1, "one flip, though the hold ran on: a kept hold holds, it starts nothing")
	assert_true(west.open)
	assert_eq(int(Variants.number(flips[0][2])) - started[0], 29, "the flip lands on the action's 30th tick")
	var clangs: Array[NoiseSystem.Event] = C.clangs(s)
	assert_eq(clangs.size(), 1, "exactly one clang")
	assert_eq(clangs[0].tick, int(Variants.number(flips[0][2])), "on the flip's tick")
	assert_eq(clangs[0].level_np, 14.0)
	assert_eq(clangs[0].origins, west.clang_origins(), "at the gateway")
	for t: Vector2i in west.tiles:
		assert_true(s.run.mine.native.is_walkable(t, false), "open: floor")
	# Released, then a fresh action shuts it.
	s.step(5)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 40)
	s.step(60)
	assert_false(west.open)
	assert_eq(flips.size(), 2)
	assert_eq(C.clangs(s).size(), 2)
	for t: Vector2i in west.tiles:
		assert_eq(s.run.mine.native.effective_material(t), WorldIds.TileMaterial.STEEL)


func test_early_release_changes_nothing() -> void:
	var parts: Array = _setup(13)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var ann: MinerHandle = parts[2]
	var west: Gate = camp.gate_system.gate("west")
	var most: Array[int] = [0]
	s.on_tick = func(_sc: Scenario) -> void:
		var a: Gate.LeverAction = west.actions.get(ann.entity_id, null)
		if a != null:
			most[0] = maxi(most[0], a.ticks_done)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 29)
	s.step(60)
	assert_eq(most[0], 29, "29 of 30 ticks held")
	assert_false(west.open)
	assert_true(west.actions.is_empty(), "the action ended on release")
	assert_eq(C.clangs(s).size(), 0)
	assert_eq(camp.gate_system.diff_log.size(), 0)
	# A second short hold starts over; it does not add to the first.
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 20)
	s.step(40)
	assert_false(west.open)


func test_out_of_reach_does_nothing() -> void:
	var parts: Array = _setup(14)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var bob: MinerHandle = s.add_miner("bob", Basecamp.deck_rect(C.SEED, 0).position)
	s.step(2)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	s.step(80)
	for g: Gate in camp.gate_system.gates:
		assert_false(g.open, "nobody in touch range of a lever")
	assert_eq(C.clangs(s).size(), 0)


func test_outside_lever_works_too() -> void:
	var s: Scenario = make({"seed": 15, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var cy: MinerHandle = s.add_miner("cy", C.lever(s, "south", "outside"))
	s.step(2)
	cy.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 40)
	s.step(60)
	assert_true(camp.gate_system.gate("south").open, "levers work from either side")
	assert_false(camp.gate_system.gate("west").open)
	assert_false(camp.gate_system.gate("east").open)
