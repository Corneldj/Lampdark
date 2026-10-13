extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02: every flip is a diff-log entry and raises sealed_changed the same tick; gate states
## survive base camp's cell being evicted and reloaded, and a resume, quietly (no clang).

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _open_west(s: Scenario) -> void:
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(50)


func test_flips_are_logged_and_unseal_the_same_tick() -> void:
	var s: Scenario = make({"seed": 61, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var flips: Array[int] = []
	var seals: Array[Array] = []
	camp.gate_system.flipped.connect(func(_side: String, _open: bool) -> void: flips.append(s.run.tick))
	camp.sealed_changed.connect(func(on: bool) -> void: seals.append([on, s.run.tick]))
	s.step(1)
	assert_true(camp.is_sealed())
	_open_west(s)
	assert_eq(flips.size(), 1)
	assert_eq(seals, [[false, flips[0]]], "sealed_changed on the flip's tick")
	assert_eq(camp.gate_system.diff_log, [{"tick": flips[0], "side": "west", "open": true}])


func test_survives_eviction() -> void:
	var s: Scenario = make({"seed": 62, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	_open_west(s)
	var west: Gate = camp.gate_system.gate("west")
	assert_true(west.open)
	var clangs: int = C.clangs(s).size()
	s.run.mine.native.unload(Vector2i.ZERO)
	s.step(2)
	# Reloaded as authored: all three open on the tiles until the record is put back.
	s.run.mine.native.commit(Basecamp.cell_data(C.SEED, 0))
	s.run.light.grid.on_cell_loaded(Vector2i.ZERO)
	s.step(2)
	for g: Gate in camp.gate_system.gates:
		var steel: bool = s.run.mine.native.effective_material(g.tiles[0]) == WorldIds.TileMaterial.STEEL
		assert_eq(steel, not g.open, "%s back as recorded" % g.side)
	assert_true(west.open)
	assert_false(camp.gate_system.gate("east").open)
	assert_eq(C.clangs(s).size(), clangs, "a reload makes no sound")


func test_survives_resume() -> void:
	var a: Scenario = make({"seed": 63, "fixture": C.scenario_fixture()})
	var camp_a: BaseCampState = C.load_camp(a)
	_open_west(a)
	var saved: Array[Dictionary] = camp_a.gate_system.snapshot()
	assert_eq(saved.size(), 3)
	var b: Scenario = make({"seed": 63, "fixture": C.scenario_fixture()})
	var camp_b: BaseCampState = C.load_camp(b, 0, false)
	camp_b.gate_system.restore(b.run, saved)
	b.step(2)
	for g: Gate in camp_b.gate_system.gates:
		var was: Gate = camp_a.gate_system.gate(g.side)
		assert_eq(g.open, was.open, g.side)
		assert_eq(g.opened_tick, was.opened_tick, g.side)
		var steel: bool = b.run.mine.native.effective_material(g.tiles[0]) == WorldIds.TileMaterial.STEEL
		assert_eq(steel, not g.open)
	var west: Gate = camp_b.gate_system.gate("west")
	assert_ne(west.spill, 0, "the open gate's spill is back")
	assert_almost_eq(b.run.light.light_at(west.middle() + west.outward), a.run.light.light_at(west.middle() + west.outward), 1e-9)
	assert_eq(C.clangs(b).size(), 0, "a resume makes no sound")
	assert_false(camp_b.is_sealed())
