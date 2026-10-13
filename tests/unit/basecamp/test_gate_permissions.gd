extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02: only a conscious miner (Upright or Caught) with a free hand works a lever. A Hand,
## Bess, a creature, the Grabbed, the unconscious and the dead never do. Creature navigation never
## routes through a shut gate.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _try(run_seed: int, prepare: Callable) -> bool:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	s.step(2)
	prepare.call(s, camp, ann)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 40)
	s.step(60)
	return camp.gate_system.gate("west").open


func test_upright_and_caught_may() -> void:
	assert_true(_try(51, func(_s: Scenario, _c: BaseCampState, _a: MinerHandle) -> void: pass), "Upright")
	var caught: Callable = func(s: Scenario, _c: BaseCampState, a: MinerHandle) -> void:
		s.run.miner_state.enter_caught(a.entity_id, &"test", 0)
	assert_true(_try(52, caught), "Caught")


func test_hand_is_refused() -> void:
	var hand: Callable = func(s: Scenario, _c: BaseCampState, a: MinerHandle) -> void:
		s.run.crew.is_hand_driven = func(e: int) -> bool: return e == a.entity_id
	assert_false(_try(53, hand), "Hired Hands never work gates")


func test_no_free_hand_is_refused() -> void:
	var full: Callable = func(_s: Scenario, c: BaseCampState, _a: MinerHandle) -> void:
		c.gate_system.free_hand = func(_e: int) -> bool: return false
	assert_false(_try(54, full), "carrying two-handed")


func test_grabbed_unconscious_dead_are_refused() -> void:
	var grabbed: Callable = func(s: Scenario, _c: BaseCampState, a: MinerHandle) -> void:
		s.run.miner_state.enter_grabbed(a.entity_id, &"test", 0)
	assert_false(_try(55, grabbed), "Grabbed")
	var fallen: Callable = func(s: Scenario, _c: BaseCampState, a: MinerHandle) -> void:
		s.run.miner_state.fall_unconscious(a.entity_id, "test")
	assert_false(_try(56, fallen), "unconscious")
	var dead: Callable = func(s: Scenario, _c: BaseCampState, a: MinerHandle) -> void:
		s.run.miner_state.kill(a.entity_id, "test")
	assert_false(_try(57, dead), "dead")


func test_bess_and_creatures_are_never_workers() -> void:
	var s: Scenario = make({"seed": 58, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var at: Vector2 = Vector2(C.lever(s, "west", "inside")) + Vector2(0.5, 0.5)
	for kind: WorldIds.EntityKind in [WorldIds.EntityKind.BESS, WorldIds.EntityKind.MOTH, WorldIds.EntityKind.TAPPER,
			WorldIds.EntityKind.STYTHE, WorldIds.EntityKind.TAPPER_ARM]:
		var id: int = C.place_body(s, kind, at)
		assert_false(camp.gate_system.may_work(s.run, id), str(WorldIds.EntityKind.find_key(kind)))
	var ann: MinerHandle = s.add_miner("ann", Basecamp.deck_rect(C.SEED, 0).position)
	assert_true(camp.gate_system.may_work(s.run, ann.entity_id))


func test_creature_nav_never_crosses_a_shut_gate() -> void:
	var s: Scenario = make({"seed": 59, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	s.step(1)
	var nav: CreatureNav = CreatureNav.new(s.run.mine, s.run.light)
	var deck: Vector2 = Vector2(Basecamp.deck_rect(C.SEED, 0).get_center())
	for g: Gate in camp.gate_system.gates:
		var road: Vector2i = g.middle() + g.outward * 4
		assert_false(nav.moth_path_within(road, deck), "%s shut: no walker path in" % g.side)
		assert_false(nav.stythe_dark_path_within(road, deck), "%s shut: no dark path in" % g.side)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(1)
	assert_true(nav.moth_path_within(west.middle() + west.outward * 4, deck), "open: the walker path runs through it")
