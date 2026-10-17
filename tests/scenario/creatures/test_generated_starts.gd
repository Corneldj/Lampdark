extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-18: a generated run's three creatures start at their homes (CreatureStarts), against GEN-10's
## homes and GEN-08's plan:
## - the Moth asleep in its start roost's chamber (or by the hoard);
## - the Tapper in Tapper-rich rock in rings 1-2 (a staged run 1: rings 0-1);
## - the Stythe at its lair.
## A watched start tile makes a start wait, none spawns twice, a creature turned off and the Tapper
## under Quiet Seam never spawn, and a resumed run spawns nothing new.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## GEN-07's road pack with every biome's grid given a high chamber (the square between its first two
## road lines, 6 to 8 across: a roost) and a Tapper-rich rock mass (its 4x4 north-west block).
static func starts_pack() -> PackedByteArray:
	var specs: Array = [Specs.main_road_spec("main_straight", "straight", false), Specs.main_road_spec("main_bend_5", "bend_5", false),
		Specs.main_road_spec("main_bend_10", "bend_10", false), Specs.main_road_spec("main_bend_15", "bend_15", false),
		Specs.main_road_spec("main_crossing", "crossing", false), Specs.main_road_spec("main_straight_oldfall", "straight", true)]
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		var grid: Dictionary = Specs.grid_spec("%s_grid" % biome, "biome_cell", biome, 1.0)
		var w: int = int(Variants.number(Specs.BIOME_WIDTH.get(biome, 3)))
		var lo: int = 5 - w / 2
		var hi: int = 10 - w / 2 + w - 1
		var rows: Array = Variants.array(grid["rows"]).duplicate()
		for y: int in range(lo, hi + 1):
			var row: String = rows[y]
			rows[y] = row.substr(0, lo) + ".".repeat(hi - lo + 1) + row.substr(hi + 1)
		grid["rows"] = rows
		var anchors: Array = Variants.array(grid["anchors"]).duplicate()
		anchors.append(["chamber", lo, lo, hi - lo + 1, hi - lo + 1, ["high"], ""])
		anchors.append(["rich_rock", 0, 0, 4, 4, [], ""])
		grid["anchors"] = anchors
		specs.append(grid)
		specs.append(Specs.grid_spec("%s_plain" % biome, "fallback", biome, 1.0))
	var problems: Array[String] = []
	var out: PackedByteArray = Specs.pack(specs, problems)
	assert(problems.is_empty(), str(problems))
	return out


func _make(run_seed: int, extra: Dictionary = {}, top: Dictionary = {}) -> Scenario:
	var generated: Dictionary = {"pack": starts_pack(), "plan": true, "creatures": true}
	generated.merge(extra, true)
	var cfg: Dictionary = {"seed": run_seed, "generated": generated}
	cfg.merge(top, true)
	return make(cfg)


static func _creature(s: Scenario, kind: WorldIds.EntityKind) -> Creature:
	for c: Creature in s.run.creatures.creatures:
		if c.kind == kind:
			return c
	return null


static func _lair_cells(layouts: LbLayouts) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for raw: Variant in Variants.array(layouts.plan_dict()["sites"]):
		var site: Dictionary = Variants.dict(raw)
		if str(site["kind"]) == "lair":
			out.assign(Variants.array(site["cells"]))
	return out


func test_each_creature_starts_at_its_home() -> void:
	var rings: Vector2 = Tuning.range_f(&"tapper.start_rings")
	var at_roost: int = 0
	for run_seed: int in [5101, 5113, 5119, 5147]:
		var s: Scenario = _make(run_seed)
		var layouts: LbLayouts = s.generation.layouts
		var homes: Dictionary = layouts.homes_dict()
		for kind: String in ["moth", "tapper", "stythe"]:
			assert_eq(int(Variants.number(Variants.dict(s.starts[kind])["result"])), OK, "seed %d: the %s started" % [run_seed, kind])
		# The Moth asleep at its start roost (or by the hoard), that tile its roost.
		var moth: Moth = _creature(s, WorldIds.EntityKind.MOTH) as Moth
		assert_not_null(moth)
		var mt: Vector2i = moth.tile(s.run)
		assert_true(moth.is_sleeping(), "seed %d: the Moth starts asleep" % run_seed)
		assert_eq(moth.roost, mt)
		var start: int = int(Variants.number(homes["start_roost"]))
		if start >= 0:
			var r: Rect2i = Variants.array(homes["roosts"])[start]
			assert_true(r.has_point(mt), "seed %d: on its start roost's chamber %s, at %s" % [run_seed, r, mt])
			at_roost += 1
		else:
			var hoard: Vector2i = homes["hoard"]
			assert_lt(Vector2(mt).distance_to(Vector2(hoard)), 15.0, "by the hoard")
		# The Tapper in a rich-rock mass in rings 1-2, reading the masses.
		var tapper: Tapper = _creature(s, WorldIds.EntityKind.TAPPER) as Tapper
		assert_not_null(tapper)
		var tt: Vector2i = tapper.tile(s.run)
		assert_true(s.run.placed.is_rich_rock(tt), "seed %d: the Tapper rests in Tapper-rich rock at %s" % [run_seed, tt])
		assert_between(WorldCoords.ring_of_tile(tt), roundi(rings.x), roundi(rings.y))
		assert_true(tapper.rich_rock.is_valid())
		# The Stythe at its lair, measured from there.
		var stythe: StytheCreature = _creature(s, WorldIds.EntityKind.STYTHE) as StytheCreature
		assert_not_null(stythe)
		var st: Vector2i = stythe.tile(s.run)
		assert_eq(stythe.lair, st)
		assert_true(_lair_cells(layouts).has(WorldCoords.cell_of(st)), "seed %d: in the lair site's cells" % run_seed)
		assert_eq(s.run.creatures.creatures.size(), 3)
	assert_gt(at_roost, 0, "some Moths at a roost")


func test_a_watched_start_tile_waits_and_none_spawns_twice() -> void:
	var s: Scenario = _make(5101, {"creatures": false, "home_windows": true})
	var layouts: LbLayouts = s.generation.layouts
	var tile: Variant = CreatureStarts.moth_tile(s.run, layouts.homes_dict())
	assert_true(tile != null, "a start tile for the Moth")
	var at: Vector2i = tile
	# A miner beside the Moth's start tile, facing it, her lamp lighting it.
	var by: Vector2i = CreatureStarts.nearest_floor(s.run, at + Vector2i(2, 0), 4)
	var ann: MinerHandle = s.add_miner("ann", by, {"facing_deg": 180.0})
	ann.at(0).face(180.0)
	var lamp: int = s.run.light.grid.add_point("gauze_lamp", 1, ann.entity_id, 0, 4.0, 1.0, Vector2(by) + Vector2(0.5, 0.5), 0)
	s.step(3)
	assert_true(s.run.vision.native.is_seen_or_margin_of_any(at))
	var first: Dictionary = CreatureStarts.spawn(s.run, layouts)
	assert_eq(int(Variants.number(Variants.dict(first["moth"])["result"])), ERR_BUSY, "a watched start tile: it waits")
	assert_push_error("seen or in a margin")
	assert_null(_creature(s, WorldIds.EntityKind.MOTH))
	# A second start makes no second creature of any kind, and no error. (The lair's window has gone
	# with no holder near it by now, so its Stythe finds no start; a real run starts before its first tick.)
	var again: Dictionary = CreatureStarts.spawn(s.run, layouts)
	assert_eq(int(Variants.number(Variants.dict(again["moth"])["result"])), ERR_ALREADY_EXISTS, "the waiting Moth is the run's one")
	assert_eq(int(Variants.number(Variants.dict(again["tapper"])["result"])), ERR_ALREADY_EXISTS)
	for kind: WorldIds.EntityKind in [WorldIds.EntityKind.MOTH, WorldIds.EntityKind.TAPPER, WorldIds.EntityKind.STYTHE]:
		assert_lte(s.run.creatures.count_of(kind), 1, "one at most of each")
	# Dark again: it appears there, once.
	s.run.light.grid.remove_source(lamp)
	s.step(3)
	var moth: Creature = _creature(s, WorldIds.EntityKind.MOTH)
	assert_not_null(moth)
	assert_eq(moth.tile(s.run), at)
	var moths: int = 0
	for id: int in s.run.registry.ids():
		if s.run.registry.get_entity(id).kind == WorldIds.EntityKind.MOTH:
			moths += 1
	assert_eq(moths, 1)


func test_a_staged_run_ones_tapper_starts_in_ring_0_or_1_rock() -> void:
	assert_eq(CreatureStarts.tapper_rings("1"), Tuning.range_f(&"modes.staging_tapper_start_rings"))
	assert_eq(CreatureStarts.tapper_rings(""), Tuning.range_f(&"tapper.start_rings"))
	var staged: Vector2 = Tuning.range_f(&"modes.staging_tapper_start_rings")
	for run_seed: int in [5101, 5113]:
		var s: Scenario = _make(run_seed, {"plan_overrides": {"staging": "1"}})
		assert_eq(str(s.generation.layouts.plan_dict()["staging"]), "1")
		var tapper: Creature = _creature(s, WorldIds.EntityKind.TAPPER)
		assert_not_null(tapper)
		var tt: Vector2i = tapper.tile(s.run)
		assert_between(WorldCoords.ring_of_tile(tt), roundi(staged.x), roundi(staged.y), "seed %d: ring 0-1 rock" % run_seed)
		assert_true(s.run.placed.is_rich_rock(tt))


func test_a_creature_turned_off_and_the_tapper_under_quiet_seam_never_spawn() -> void:
	Tuning.set_dev_override("creatures.enabled", {"moth": 0, "tapper": 1, "stythe": 1})
	var s: Scenario = _make(5113)
	Tuning.clear_dev_overrides()
	assert_eq(int(Variants.number(Variants.dict(s.starts["moth"])["result"])), ERR_UNAVAILABLE)
	assert_null(_creature(s, WorldIds.EntityKind.MOTH), "off in creatures.enabled")
	assert_not_null(_creature(s, WorldIds.EntityKind.TAPPER))
	assert_not_null(_creature(s, WorldIds.EntityKind.STYTHE))
	var quiet: Scenario = _make(5113, {"creatures": false, "home_windows": true})
	quiet.run.creatures.conditions = ["quiet_seam"]
	var starts: Dictionary = CreatureStarts.spawn(quiet.run, quiet.generation.layouts)
	assert_eq(int(Variants.number(Variants.dict(starts["tapper"])["result"])), ERR_UNAVAILABLE)
	assert_null(_creature(quiet, WorldIds.EntityKind.TAPPER), "no Tapper under Quiet Seam")
	assert_not_null(_creature(quiet, WorldIds.EntityKind.MOTH))
	assert_not_null(_creature(quiet, WorldIds.EntityKind.STYTHE))


func test_a_resumed_run_spawns_nothing_new() -> void:
	S.clear(5119)
	var s: Scenario = _make(5119, {}, {"saves": true})
	var home: Vector2i = CreatureStarts.nearest_floor(s.run, Vector2i(10, 10), 6)
	var ann: MinerHandle = s.add_miner("ann", home)
	ann.brain = null
	assert_true(S.until_saved(s, 1))
	var saved: Dictionary = {}
	for c: Creature in s.run.creatures.creatures:
		saved[c.kind] = c.tile(s.run)
	assert_eq(saved.size(), 3)
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var opened: Dictionary = SaveResume.open_file(path)
	assert_true(Variants.flag(opened["ok"]), str(opened["message"]))
	# As server_main resumes: no creature starts, the save's creatures restored.
	var b: Scenario = _make(5119, {"creatures": false, "home_windows": true}, {"saves": true})
	SaveResume.apply(b.run, b.net, opened)
	assert_eq(b.run.creatures.creatures.size(), 3, "the save's three")
	for c: Creature in b.run.creatures.creatures:
		var want: Vector2i = saved[c.kind]
		assert_eq(c.tile(b.run), want, "%s where it was saved" % c.kind_name())
	# And a start called anyway keeps them.
	var starts: Dictionary = CreatureStarts.spawn(b.run, b.generation.layouts)
	for kind: String in ["moth", "tapper", "stythe"]:
		assert_eq(int(Variants.number(Variants.dict(starts[kind])["result"])), ERR_ALREADY_EXISTS, kind)
	assert_eq(b.run.creatures.creatures.size(), 3)
