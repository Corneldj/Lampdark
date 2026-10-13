extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02: under the public flag an unheld gate swings shut basecamp.gate_public_autoclose_s
## (400 ticks) after its open flip, with its clang; a held one stays open and shuts on release
## once the time has passed; an occupied one waits for the first clear tick. Non-public runs
## never auto-close.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _open_by_lever(run_seed: int, mode: ServerConfig.Mode, hold_ticks: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture(), "mode": mode})
	var camp: BaseCampState = C.load_camp(s)
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	s.step(2)
	var flips: Array[Array] = []
	camp.gate_system.flipped.connect(func(_side: String, open: bool) -> void: flips.append([open, s.run.tick]))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, hold_ticks)
	return [s, camp, ann, flips]


func test_unheld_public_gate_shuts_after_20_s() -> void:
	var parts: Array = _open_by_lever(41, ServerConfig.Mode.PUBLIC, 30)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var flips: Array[Array] = parts[3]
	assert_eq(roundi(Tuning.f(&"basecamp.gate_public_autoclose_s") * 20.0), 400)
	s.step(500)
	assert_eq(flips.size(), 2)
	assert_eq(Variants.flag(flips[0][0]), true)
	assert_eq(Variants.flag(flips[1][0]), false, "swung shut by itself")
	assert_eq(int(Variants.number(flips[1][1])) - int(Variants.number(flips[0][1])), 400, "on the first tick with 20 s passed")
	assert_eq(C.clangs(s).size(), 2, "the auto-close clangs too")
	assert_false(camp.gate_system.gate("west").open)


func test_held_gate_shuts_on_release() -> void:
	var parts: Array = _open_by_lever(42, ServerConfig.Mode.PUBLIC, 600)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var ann: MinerHandle = parts[2]
	var flips: Array[Array] = parts[3]
	var west: Gate = camp.gate_system.gate("west")
	var last_held: Array[int] = [-1]
	s.on_tick = func(_sc: Scenario) -> void:
		if west.holders.has(ann.entity_id):
			last_held[0] = s.run.tick - 1
	s.step(500)
	assert_eq(flips.size(), 1, "held past 20 s: still open")
	assert_true(west.open)
	s.step(200)
	assert_eq(flips.size(), 2)
	assert_eq(Variants.flag(flips[1][0]), false)
	assert_eq(int(Variants.number(flips[1][1])), last_held[0] + 1, "shut on the first tick after release")


func test_occupied_gate_waits_for_clear() -> void:
	var parts: Array = _open_by_lever(43, ServerConfig.Mode.PUBLIC, 30)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var flips: Array[Array] = parts[3]
	var west: Gate = camp.gate_system.gate("west")
	s.step(60)
	var bess: int = C.place_body(s, WorldIds.EntityKind.BESS, Vector2(west.middle()) + Vector2(0.5, 0.5))
	s.step(500)
	assert_true(west.open, "waits while Bess stands in the doorway")
	assert_eq(flips.size(), 1)
	s.run.registry.destroy(bess)
	var cleared: int = s.run.tick
	s.step(3)
	assert_eq(flips.size(), 2)
	assert_eq(int(Variants.number(flips[1][1])), cleared, "on the first clear tick")


func test_friends_runs_never_auto_close() -> void:
	var parts: Array = _open_by_lever(44, ServerConfig.Mode.FRIENDS, 30)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var flips: Array[Array] = parts[3]
	s.step(1200)
	assert_eq(flips.size(), 1)
	assert_true(camp.gate_system.gate("west").open)
