extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02: a lamp opened across a Stythe's path invalidates it that tick; the Stythe replans and
## never steps onto a tile lit to its threshold; with no dark way on, it makes for the reachable
## dark tile nearest its target.

const N = preload("res://tests/unit/creatures/nav_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())
	Tuning.set_dev_override("creatures.enabled", {"moth": 1, "tapper": 1, "stythe": 1})


func after_all() -> void:
	Tuning.clear_dev_overrides()


func test_lamp_across_the_path() -> void:
	var s: Scenario = make({"seed": 21, "fixture": FixtureMap.from_ascii(N.chambers())})
	assert_ne(s.place_stand_in(WorldIds.EntityKind.STYTHE, Vector2i(1, 6)), 0)
	var stythe: KitCreature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.STYTHE)
	stythe.follower = NavFollower.new()
	stythe.speed = 3.0
	stythe.max_speed = 3.0
	var dark: Dictionary = NavModes.dark()
	stythe.follower.go(s.run, s.run.creatures.nav, stythe, Vector2i(32, 6), NavModes.Mode.DARK, dark)
	var threshold: float = Tuning.f(&"stythe.wall_level")
	var lit_at: Array[int] = [-1]
	var replans_then: Array[int] = [0]
	var stepped_lit: Array[Vector2i] = []
	var lamp: Array[int] = [0]
	s.on_tick = func(sc: Scenario) -> void:
		var t: Vector2i = stythe.tile(sc.run)
		if sc.run.light.light_at(t) >= threshold and sc.run.tick - 1 > lit_at[0]:
			stepped_lit.append(t)
		if sc.run.tick == 6:
			# A lamp opens in the corridor ahead (it lights in the next tick's light pass).
			lamp[0] = sc.run.light.grid.add_point("gauze_lamp", 1, 0, 0, 5.0, 1.0, Vector2(16.5, 6.5), 0)
			lit_at[0] = sc.run.tick
			replans_then[0] = stythe.follower.replans
	s.step(8)
	assert_gt(stythe.follower.replans, replans_then[0], "the path crossing the new light was replanned in the tick it lit")
	s.step(500)
	assert_eq(stepped_lit, [] as Array[Vector2i], "never onto a lit tile")
	assert_eq(stythe.follower.status, NavFollower.Status.ARRIVED, "it went the long way round, through the dark")
	assert_eq(stythe.tile(s.run), Vector2i(32, 6))
	# Light the north road too: no dark way back west remains.
	s.run.light.grid.add_point("gauze_lamp", 1, 0, 0, 5.0, 1.0, Vector2(16.5, 1.5), 0)
	s.step(2)
	stythe.follower.go(s.run, s.run.creatures.nav, stythe, Vector2i(1, 6), NavModes.Mode.DARK, dark)
	s.step(500)
	var heading: Vector2i = stythe.follower.heading_for
	gut.p("both ways lit: the Stythe settles at %s for a target of (1, 6)" % heading)
	assert_ne(heading, Vector2i(1, 6), "no dark path: it makes for the reachable dark tile nearest the target")
	assert_eq(stythe.tile(s.run), heading)
	assert_lt(s.run.light.light_at(heading), threshold)
	assert_eq(stepped_lit, [] as Array[Vector2i], "and never onto a lit tile")
	assert_eq(s.run.creatures.teleport_violations, 0)
