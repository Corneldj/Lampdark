extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-01 (scn_motion_prediction_parity): given the same input stream, the shared step run as a
## client would (pure, from the applied inputs) lands on exactly the server's positions.

const ROWS: PackedStringArray = [
	"####################",
	"#a.......#.........#",
	"#....#.......###...#",
	"#....#.............#",
	"####################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_identical_positions() -> void:
	var s: Scenario = make({"seed": 33, "fixture": FixtureMap.from_ascii(ROWS)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bot: RefCounted = load("res://tools/bots/brain.gd").call(&"create", "wander", 77)
	ann.brain = bot
	var server_positions: Array[Vector2] = []
	s.on_tick = func(sc: Scenario) -> void:
		var m: MovementSystem.Miner = sc.run.movement.miner(ann.slot)
		server_positions.append(Vector2(m.state.x, m.state.y))
	s.step(400)
	# The client side: the same pure step over the inputs the server applied, against the same tiles.
	var mine: Mine = s.mine
	var is_solid: Callable = func(t: Vector2i) -> bool: return not mine.native.is_walkable(t)
	var state: MinerMotion.State = MinerMotion.State.new()
	state.x = s.fixture.spot("a").x + 0.5
	state.y = s.fixture.spot("a").y + 0.5
	var p: MinerMotion.Params = MinerMotion.Params.from_tuning()
	var mismatches: int = 0
	var moved: float = 0.0
	for t: int in 400:
		var input: InputRecord = null
		for raw: Variant in Variants.array(s.run.inputs.recorder.by_tick.get(t, [])):
			var item: Array = Variants.array(raw)
			var c: InputBuffer.Consumed = item[1]
			input = c.record
		var before: Vector2 = Vector2(state.x, state.y)
		state = MinerMotion.step(state, input, MinerMotion.Constraints.new(), 1.0, is_solid, 0.05, p).state
		moved += (Vector2(state.x, state.y) - before).length()
		if Vector2(state.x, state.y) != server_positions[t]:
			mismatches += 1
	assert_eq(mismatches, 0, "every tick identical")
	assert_gt(moved, 20.0, "and the miner really wandered")
