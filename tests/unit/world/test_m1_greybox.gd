extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-03: the shipped grey box holds every feature the kill test needs (M1GreyboxCheck), loads base
## camp and exactly its four cells with no generator code, every maze tile is ring 0, and it loads
## in under 100 ms.

const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_shipped_maze_passes_every_requirement() -> void:
	var s: Scenario = make({"seed": 30, "fixture": MAP})
	var errors: Array[String] = M1GreyboxCheck.check(s.run.mine, MAP, {}, s.run.road_graph.graph)
	for e: String in errors:
		gut.p(e)
	assert_eq(errors.size(), 0, "every requirement holds")


func test_it_loads_base_camp_and_its_four_cells_only() -> void:
	var mine: Mine = Mine.new()
	var started: int = Time.get_ticks_usec()
	var n: int = FixedMapLoader.load_cells(mine, MAP)
	var ms: float = (Time.get_ticks_usec() - started) / 1000.0
	gut.p("loaded %d cells in %.1f ms" % [n, ms])
	assert_eq(n, 5)
	for c: Vector2i in [Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1)]:
		assert_true(mine.native.is_loaded(c), "cell %s" % c)
	assert_eq(mine.native.loaded_cells().size(), 5, "and no other")
	for c: Vector2i in [Vector2i(-1, 0), Vector2i(0, -2), Vector2i(1, 1), Vector2i(2, 0)]:
		assert_false(mine.native.is_loaded(c), "never cell %s" % c)
	assert_false(mine.native.is_walkable(Vector2i(-5, 10)), "beyond the five cells: rock")
	if OS.get_environment("LB_TIMING_REPORT_ONLY").is_empty():
		assert_lt(ms, 100.0, "loads in under 100 ms")


func test_the_placements_spawn_as_written() -> void:
	var s: Scenario = make({"seed": 34, "fixture": MAP})
	var placed: Dictionary = FixedMapLoader.populate(s.run, MAP, true, true)
	assert_not_null(s.run.base_camp, "base camp's state is installed")
	assert_eq(s.run.base_camp.run_start_check(s.run), [] as Array[String], "nothing inside base camp but what belongs")
	var heaps: Array = placed["heaps"]
	assert_eq(heaps.size(), 8, "eight coat heaps")
	for raw: Variant in heaps:
		var e: SimEntity = s.run.registry.get_entity(int(Variants.number(raw)))
		assert_eq(e.kind, WorldIds.EntityKind.COAT_HEAP)
		assert_true(s.run.lamps.hooks.has(e.tile()), "each hangs on a rib hook")
	var creatures: Dictionary = placed["creatures"]
	var moth: Moth = s.run.creatures.creature_of(int(Variants.number(creatures["MOTH"]))) as Moth
	assert_not_null(moth)
	assert_eq(moth.tile(s.run), Vector2i(4, -19), "the Moth at its start roost")
	assert_eq(moth.roost, Vector2i(4, -19), "roosting there, asleep")
	var tapper: Creature = s.run.creatures.creature_of(int(Variants.number(creatures["TAPPER"])))
	assert_not_null(tapper)
	assert_gte(s.run.mine.native.thickness(tapper.tile(s.run)), 4, "the Tapper rests in rich rock")
	var items: Array = placed["items"]
	assert_eq(items, ["FUSE", "MAGNETO", "ROPE_CLAMP", "GAUZE_LAMP", "GAUZE_LAMP", "OIL_FLASK", "OIL_FLASK"])
	assert_gte(int(Variants.number(placed["hooks"])), 40, "every timber hook hung (MNR-06)")
	for i: int in s.run.base_camp.gates.size():
		var g: Dictionary = s.run.base_camp.gates[i]
		assert_false(s.run.base_camp.gate_system.gate(str(g["side"])).open, "a fresh run: the %s gate shut" % g["side"])
