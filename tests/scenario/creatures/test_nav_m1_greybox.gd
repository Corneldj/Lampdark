extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02's grey-box checks (test_nav_grey_box.gd's) repeated on GEN-03's grey box itself: every mode
## reaches the maze's goals and reports none for what it cannot; the Moth holds at the hoard's air
## door, passes and leaves it shut; a shut gate never opens for it; the Tapper never stands in brick.

const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func _walker(s: Scenario, kind: WorldIds.EntityKind, at: Vector2i, speed: float) -> KitCreature:
	assert_ne(s.place_stand_in(kind, at), 0)
	var c: KitCreature = s.run.creatures.creature_of_kind(kind)
	c.follower = NavFollower.new()
	c.speed = speed
	c.max_speed = speed
	return c


func test_every_mode_reaches_or_reports() -> void:
	var s: Scenario = make({"seed": 40, "fixture": MAP})
	var nav: CreatureNav = s.run.creatures.nav
	var camp: Vector2i = Vector2i(6, 6)
	var unloaded: Vector2i = Vector2i(-6, 10)
	for mode: NavModes.Mode in [NavModes.Mode.WALKER, NavModes.Mode.CRAWLER, NavModes.Mode.DARK]:
		for goal: Vector2i in M1GreyboxCheck.walk_targets(s.mine, MAP):
			if goal == Vector2i(25, 16):
				continue  # the hoard: behind the shut air door (the Moth's hold is tested below)
			assert_true(Variants.flag(nav.native.path(mode, camp, goal)["found"]), "mode %d reaches %s" % [mode, goal])
		assert_false(Variants.flag(nav.native.path(mode, camp, unloaded)["found"]), "mode %d reports none beyond the maze" % mode)
	var rock: Dictionary = nav.native.path(NavModes.Mode.ROCK, Vector2i(28, -12), Vector2i(26, 3))
	assert_true(Variants.flag(rock["found"]), "the Tapper's rock path from the pillar to the east block")
	for raw: Variant in Variants.array(rock["tiles"]):
		var t: Vector2i = raw
		assert_ne(s.mine.native.material_at(t), WorldIds.TileMaterial.BRICK, "never through brick (%s)" % t)
	assert_false(Variants.flag(nav.native.path(NavModes.Mode.ROCK, Vector2i(28, -12), unloaded)["found"]))


func test_the_moth_holds_at_the_hoard_door_and_a_shut_gate_never_opens() -> void:
	var s: Scenario = make({"seed": 41, "fixture": MAP})
	var moth: KitCreature = _walker(s, WorldIds.EntityKind.MOTH, Vector2i(25, 9), 2.5)
	var door: Vector2i = Vector2i(25, 12)
	moth.follower.go(s.run, s.run.creatures.nav, moth, Vector2i(25, 15), NavModes.Mode.WALKER)
	var held: Array[int] = []
	var door_states: Array[int] = []
	s.on_tick = func(sc: Scenario) -> void:
		if moth.follower.status == NavFollower.Status.HOLDING:
			held.append(sc.run.tick)
		door_states.append(sc.run.mine.native.state_at(door))
	s.step(200)
	assert_eq(held.size(), roundi(Tuning.f(&"moth.air_door_hold_s") * Tuning.f(&"net.tick_hz")), "held at the shut air door")
	assert_eq(moth.follower.status, NavFollower.Status.ARRIVED, "then it passed")
	assert_false(door_states.has(1), "and the door stayed shut")
	# The south gate shut: from the south arm there is no other way into base camp.
	s.on_tick = Callable()
	var t: Scenario = make({"seed": 42, "fixture": MAP})
	assert_true(t.mine.native.set_barrier(Vector2i(0, 0), 1, false))
	var m2: KitCreature = _walker(t, WorldIds.EntityKind.MOTH, Vector2i(10, 24), 2.5)
	m2.follower.go(t.run, t.run.creatures.nav, m2, Vector2i(10, 15), NavModes.Mode.WALKER)
	assert_eq(m2.follower.status, NavFollower.Status.BLOCKED, "a shut gate never opens for it")
	var tiles: Array[Vector2i] = []
	t.on_tick = func(sc: Scenario) -> void: tiles.append(m2.tile(sc.run))
	t.step(60)
	for g: Vector2i in [Vector2i(9, 18), Vector2i(10, 18), Vector2i(11, 18)]:
		assert_false(tiles.has(g), "never on the gate (%s)" % g)
	assert_eq(t.run.creatures.teleport_violations, 0)
