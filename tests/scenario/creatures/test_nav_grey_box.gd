extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02 walked by creatures, tick by tick, on a fixture of corridors, chambers, an air door, a
## gate and a brick-lined room (GEN-03's grey box repeats this when it lands): every mode reaches
## what it can and reports what it cannot; the Moth holds 60 ticks at a closed air door, passes
## and leaves it shut, and never crosses a shut gate; a prowl hugs the ribs; the Tapper never
## stands in brick.

const N = preload("res://tests/unit/creatures/nav_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _walker(s: Scenario, kind: WorldIds.EntityKind, at: Vector2i, speed: float) -> KitCreature:
	assert_ne(s.place_stand_in(kind, at), 0)
	var c: KitCreature = s.run.creatures.creature_of_kind(kind)
	c.follower = NavFollower.new()
	c.speed = speed
	c.max_speed = speed
	return c


func test_air_door_hold_and_gate() -> void:
	var rows: PackedStringArray = N.road(30)
	rows[2] = "#........D..............G.....#"
	var s: Scenario = make({"seed": 11, "fixture": FixtureMap.from_ascii(rows)})
	var moth: KitCreature = _walker(s, WorldIds.EntityKind.MOTH, Vector2i(1, 2), 2.5)
	var door: Vector2i = Vector2i(9, 2)
	moth.follower.go(s.run, s.run.creatures.nav, moth, Vector2i(15, 2), NavModes.Mode.WALKER)
	var held: Array[int] = []
	var door_states: Array[int] = []
	s.on_tick = func(sc: Scenario) -> void:
		if moth.follower.status == NavFollower.Status.HOLDING:
			held.append(sc.run.tick)
		door_states.append(sc.run.mine.native.state_at(door))
	s.step(220)
	assert_eq(held.size(), 60, "held 60 ticks (3.0 s) at the closed air door")
	assert_eq(held[held.size() - 1] - held[0], 59, "in one stretch")
	assert_eq(moth.follower.status, NavFollower.Status.ARRIVED, "then it passed")
	assert_false(door_states.has(1), "and the door stayed shut")
	moth.follower.go(s.run, s.run.creatures.nav, moth, Vector2i(28, 2), NavModes.Mode.WALKER)
	assert_eq(moth.follower.status, NavFollower.Status.BLOCKED, "a shut gate never opens for it")
	var tiles: Array[Vector2i] = []
	s.on_tick = func(sc: Scenario) -> void: tiles.append(moth.tile(sc.run))
	s.step(60)
	assert_false(tiles.has(Vector2i(24, 2)), "never on the gate")
	assert_eq(s.run.creatures.teleport_violations, 0)


func test_every_mode_reaches_or_reports() -> void:
	var s: Scenario = make({"seed": 12, "fixture": FixtureMap.from_ascii(N.chambers())})
	var nav: CreatureNav = s.run.creatures.nav
	var cases: Array = [[NavModes.Mode.WALKER, Vector2i(1, 3), Vector2i(32, 11)], [NavModes.Mode.CRAWLER, Vector2i(1, 3), Vector2i(32, 11)],
		[NavModes.Mode.DARK, Vector2i(1, 3), Vector2i(32, 11)], [NavModes.Mode.ROCK, Vector2i(12, 4), Vector2i(36, 10)]]
	for case: Array in cases:
		var mode: NavModes.Mode = case[0]
		var from: Vector2i = case[1]
		var to: Vector2i = case[2]
		assert_true(Variants.flag(nav.native.path(mode, from, to)["found"]), "mode %d reaches %s" % [mode, to])
		var sealed: Vector2i = Vector2i(36, 5) if mode != NavModes.Mode.ROCK else Vector2i(60, 5)
		assert_false(Variants.flag(nav.native.path(mode, from, sealed)["found"]), "mode %d reports none for %s" % [mode, sealed])


func test_prowl_ratio_walked() -> void:
	var s: Scenario = make({"seed": 13, "fixture": FixtureMap.from_ascii(N.chambers())})
	var moth: KitCreature = _walker(s, WorldIds.EntityKind.MOTH, Vector2i(1, 3), 2.5)
	moth.follower.go(s.run, s.run.creatures.nav, moth, Vector2i(32, 11), NavModes.Mode.CRAWLER)
	var visited: Dictionary = {}
	s.on_tick = func(sc: Scenario) -> void: visited[moth.tile(sc.run)] = true
	s.step(400)
	assert_eq(moth.follower.status, NavFollower.Status.ARRIVED)
	var edge: int = 0
	for raw: Variant in visited.keys():
		var t: Vector2i = raw
		if s.run.creatures.nav.native.wall_adjacent(t):
			edge += 1
	gut.p("prowl walked: %d of %d tiles wall-adjacent" % [edge, visited.size()])
	assert_gte(float(edge) / visited.size(), 0.8)


func test_tapper_never_in_brick() -> void:
	var rows: PackedStringArray = PackedStringArray([
		"##############################",
		"#............................#",
		"##############BBBBBBBBBBBBBBB#",
		"##############B.............B#",
		"##############BBBBBBBBBBBBBBB#",
		"##############################",
		"##############################",
	])
	var s: Scenario = make({"seed": 14, "fixture": FixtureMap.from_ascii(rows)})
	var tapper: KitCreature = _walker(s, WorldIds.EntityKind.TAPPER, Vector2i(2, 5), 3.5)
	var seen: Dictionary = {}
	s.on_tick = func(sc: Scenario) -> void: seen[tapper.tile(sc.run)] = true
	for goal: Vector2i in [Vector2i(28, 5), Vector2i(20, 3), Vector2i(3, 0)]:
		tapper.follower.go(s.run, s.run.creatures.nav, tapper, goal, NavModes.Mode.ROCK)
		s.step(200)
	for raw: Variant in seen.keys():
		var t: Vector2i = raw
		assert_ne(s.run.mine.native.effective_material(t), WorldIds.TileMaterial.BRICK, "never in brick: %s" % t)
		assert_false(t.y == 3 and t.x >= 15 and t.x <= 27, "never in the brick-lined room: %s" % t)
	assert_gt(seen.size(), 20)
