extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-07: 1.5 s of interact at a crouch's pace or slower, with nothing identified in touch range,
## gives exactly one answer for the nearest feelable thing, at any facing, never through a wall or
## a wall corner; walking cancels it; an identified item in touch range is used instead.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const F = preload("res://tests/unit/vis/feel_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_nearest_once_at_any_facing() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(-1, 0))
	W.put(s, ItemKinds.Kind.GAUZE_LAMP, a + Vector2i(1, 1))
	ann.at(0).face(0.0)
	s.step(2)
	var seen: Array[TimedAction] = []
	s.on_tick = func(sc: Scenario) -> void:
		var act: TimedAction = sc.run.inventory.actions.get(ann.entity_id, null)
		if act != null and not seen.has(act):
			seen.append(act)
	F.feel(s, ann)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0].verb, &"feel")
	assert_eq(seen[0].ticks_needed, 30, "1.5 s")
	var got: Array[Dictionary] = F.answers(s, ann)
	assert_eq(got.size(), 1, "exactly one answer")
	assert_eq(str(got[0]["caption_key"]), "feel.item.spanner", "the nearest, behind her: facing does not matter")
	assert_eq(str(got[0]["verb_key"]), "verb.pick_up")
	assert_eq(int(Variants.number(ann.connection.feel.last_feel["bearing_q"])), 8, "west: step 8 of 16")


func test_walking_cancels() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(0, 1))
	s.step(2)
	F.feel(s, ann, 40, 0.0)
	assert_eq(F.answers(s, ann).size(), 0, "at walking pace: no answer")


func test_identified_item_is_used_not_felt() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var spanner: int = W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
	ann.at(0).face(0.0)
	s.step(4)
	F.feel(s, ann)
	assert_eq(F.answers(s, ann).size(), 0, "no feel")
	assert_false(s.run.inventory.world.items.has(spanner), "the seen spanner was picked up")


func test_never_through_a_wall_corner() -> void:
	var rows: PackedStringArray = PackedStringArray([
		"#########",
		"#.......#",
		"#...#...#",
		"#..a#...#",
		"#...##..#",
		"#.......#",
		"#########"])
	var s: Scenario = make({"seed": 4, "fixture": FixtureMap.from_ascii(rows)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	# Diagonally past the corner of two walls: (4, 3) and (3, 4)? only (4, 3) and (4, 4) are rock.
	W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 1))
	W.put(s, ItemKinds.Kind.HAMMER, a + Vector2i(-1, -1))
	s.step(2)
	F.feel(s, ann)
	var got: Array[Dictionary] = F.answers(s, ann)
	assert_eq(got.size(), 1)
	assert_eq(str(got[0]["caption_key"]), "feel.item.hammer", "the spanner past the rock corner is never felt: the next nearest is")
	assert_false(FeelSystem.clear_segment(s.run, Vector2(a) + Vector2(0.5, 0.5), Vector2(a) + Vector2(1.5, 1.5)))
	assert_true(FeelSystem.clear_segment(s.run, Vector2(a) + Vector2(0.5, 0.5), Vector2(a) + Vector2(-0.5, -0.5)))


func test_nothing_in_reach() -> void:
	var s: Scenario = make({"seed": 5, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(2)
	F.feel(s, ann)
	assert_eq(ann.connection.feel.last_feel, {"caption_key": "feel.nothing", "bearing_q": FeelMessages.NO_BEARING, "verb_key": ""})


func test_refused_when_carrying_grabbed_or_down() -> void:
	for case: String in ["carrying", "grabbed", "down"]:
		var s: Scenario = make({"seed": 6 + case.length(), "fixture": W.room()})
		var a: Vector2i = s.fixture.spot("a")
		var ann: MinerHandle = s.add_miner("ann", a)
		W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
		s.step(2)
		match case:
			"carrying":
				s.run.inventory.begin_two_handed(s.run, ann.entity_id)
			"grabbed":
				s.run.miner_state.enter_grabbed(ann.entity_id, &"drag", 0)
			"down":
				s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLAST)
		s.step(2)
		F.feel(s, ann)
		assert_eq(F.answers(s, ann).size(), 0, "%s: no feeling" % case)
