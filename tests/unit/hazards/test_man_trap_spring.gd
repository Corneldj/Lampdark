extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 (Gameplay §8.2, §4.6): springing a man-trap on purpose. Any tool, held 20 ticks from beside
## a known trap (MNR-12's action), or a thrown stone landing on its jaws (MNR-09): one snap, the trap
## spent for the run (GEN-13's record), nobody caught, the tool kept. A spent trap is offered no more.

const T = preload("res://tests/unit/hazards/trap_world.gd")
const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _offered(s: Scenario, ann: MinerHandle) -> bool:
	var t: Dictionary = s.run.inventory.targets.pick(s.run, ann.entity_id, ann.slot, s.run.inventory.world)
	return not t.is_empty() and StringName(str(t["kind"])) == &"spring_trap"


func test_a_tool_from_beside_it() -> void:
	var s: Scenario = make({"seed": 4401, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	B.light(s)
	s.step(1)
	var tile: Vector2i = s.fixture.spot("a") + Vector2i(1, 0)
	var trap: int = s.run.man_traps.place(s.run, tile, "test_jaws")
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.HAMMER)))
	s.step(3)
	assert_true(_offered(s, ann), "known (lit to 0.30) and a tool on her belt: offered")
	var snaps: int = T.events_of(s, NoiseTypes.Type.MANTRAP_SNAP).size()
	ann.at(s.run.tick + 1).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(35)
	assert_false(s.run.man_traps.is_set(trap), "spent")
	assert_eq(T.events_of(s, NoiseTypes.Type.MANTRAP_SNAP).size() - snaps, 1, "one snap")
	assert_eq(s.run.tools_parts.springs.size(), 1, "MNR-12's spring")
	assert_null(s.run.holds.caught_in(ann.entity_id), "catching nobody")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(ItemKinds.Kind.HAMMER), 1, "the tool kept")
	var cell: Vector2i = WorldCoords.cell_of(tile)
	assert_true(Variants.flag(s.run.diff_log.payload_of(cell, DiffLog.Kind.TRAP, ManTraps.KEY_PREFIX + "test_jaws").get("sprung", false)),
		"GEN-13 records it sprung")
	s.step(2)
	assert_false(_offered(s, ann), "spent, it is offered no more")
	var last: Dictionary = s.run.man_traps.history[s.run.man_traps.history.size() - 1]
	assert_eq(str(last["how"]), "tool")


func test_a_stone_on_its_jaws() -> void:
	var s: Scenario = make(T.cfg(4402))
	var trap: int = s.run.man_traps.place(s.run, T.TRAP)
	s.step(2)
	var snaps: int = T.events_of(s, NoiseTypes.Type.MANTRAP_SNAP).size()
	s.run.stones.landed.emit(T.TRAP + Vector2i(1, 0))
	assert_true(s.run.man_traps.is_set(trap), "a tile off: set still")
	s.run.stones.landed.emit(T.TRAP)
	assert_false(s.run.man_traps.is_set(trap), "under the stone: spent")
	s.run.stones.landed.emit(T.TRAP)
	s.step(2)
	assert_eq(T.events_of(s, NoiseTypes.Type.MANTRAP_SNAP).size() - snaps, 1, "one snap, never two")
	assert_true(s.run.holds.caught.is_empty(), "nobody caught")
