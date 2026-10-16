extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-14 (Gameplay §4.3, §12.4; GDD §15.8): two miners push a tub along its rails at 3.0 tiles/s,
## rumbling; a fall comes down across the road ahead of it, and the tub stops at the last rail tile
## before the rubble and never enters it, its pushers stopping with it.

## Rails along row 2 from x 2 to 17; the fall (collapse 1) chokes column 15.
const ROAD: PackedStringArray = [
	"####################",
	"#..................#",
	"#.================.#",
	"#..................#",
	"####################",
]
const FALL_X: int = 15


func before_all() -> void:
	assert_true(Tuning.load_server())


func _fixture() -> FixtureMap:
	var f: FixtureMap = FixtureMap.from_ascii(ROAD, {"=": "="})
	var standing: Array = []
	var fallen: Array = []
	for y: int in range(1, 4):
		var index: int = y * WorldIds.CELL_TILES + FALL_X
		standing.append([index, "=" if y == 2 else "."])
		fallen.append([index, "#"])
	f.cells[0]["collapses"] = [{"id": 1, "standing": standing, "fallen": fallen, "is_fallen": false}]
	return f


func test_a_tub_pushed_toward_a_fall_stops_before_its_rubble() -> void:
	var s: Scenario = make({"seed": 1531, "fixture": _fixture()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 2))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(3, 1))
	ann.at(s.run.tick).face(0.0)
	bob.at(s.run.tick).face(90.0)
	s.step(2)
	var tub: int = s.run.tubs.place(s.run, Vector2i(3, 2))
	assert_ne(tub, 0)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 26)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 26)
	s.step(29)
	assert_true(s.run.tubs.holding(ann.entity_id) and s.run.tubs.holding(bob.entity_id), "both take hold")
	assert_true(TubRails.on_rails(s.run, Vector2i(FALL_X, 2)), "the rails run on before the fall")
	var from: int = s.run.noise.event_log.size()
	var entered: Array[bool] = [false]
	s.on_tick = func(sc: Scenario) -> void:
		if sc.run.registry.get_entity(tub).position.x >= FALL_X - 0.5 + 1e-6:
			entered[0] = true
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 200)
	bob.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 200)
	s.step(30)
	var running_at: float = s.run.registry.get_entity(tub).position.x
	assert_gt(running_at, 3.5 + 2.0, "under way")
	# The roof comes down ahead of it.
	assert_true(s.run.mine.native.set_collapse(Vector2i.ZERO, 1, true))
	assert_false(TubRails.on_rails(s.run, Vector2i(FALL_X, 2)), "rubble over the rails")
	s.step(180)
	assert_eq(s.run.registry.get_entity(tub).position, Vector2(FALL_X - 0.5, 2.5), "stopped at the last rail tile before the fall")
	assert_false(entered[0], "never into it")
	var rumbles: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == NoiseTypes.Type.TUB_RUMBLE:
			rumbles += 1
	assert_gt(rumbles, 3, "it rumbled on its way")
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	s.step(20)
	assert_eq(s.run.registry.get_entity(ann.entity_id).position, at, "its pushers stop with it")
	assert_lt(at.x, FALL_X - 0.5, "behind it")
	s.on_tick = Callable()
