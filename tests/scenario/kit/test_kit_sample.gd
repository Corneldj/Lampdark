extends "res://tests/scenario/kit/scenario_test.gd"
## FND-09's sample: create, an ASCII fixture, two miners, scripted inputs, stepping, state
## queries, stream capture and a negative stream assertion.

const Sample = preload("res://tests/scenario/kit/sample.gd")


## One tick of what the server applied for a miner.
class Applied:
	extends RefCounted
	var tick: int
	var move_dir: int
	var holds: int
	var facing: int
	var actions: Array[ActionRecord]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _build() -> Scenario:
	var s: Scenario = Sample.build()
	_made.append(s)
	return s


func _track(s: Scenario, h: MinerHandle) -> Array[Applied]:
	var log: Array[Applied] = []
	s.on_tick = func(scenario: Scenario) -> void:
		var view: Dictionary = scenario.state.miner(h)
		if view["input"] == null:
			return
		var record: InputRecord = view["input"]
		var a: Applied = Applied.new()
		a.tick = scenario.run.tick - 1
		a.move_dir = record.move_dir
		a.holds = record.holds
		a.facing = record.facing
		a.actions = view["actions"]
		log.append(a)
	return log


func test_scripted_inputs_reach_the_authoritative_state() -> void:
	var s: Scenario = _build()
	var ann: MinerHandle = s.miners[0]
	var log: Array[Applied] = _track(s, ann)
	s.step(30)
	assert_eq(s.run.tick, 30)
	assert_eq(ann.inputs_sent, 30, "one input per tick")
	var east: int = log.filter(func(a: Applied) -> bool: return a.move_dir == 0).size()
	assert_eq(east, 10, "ten ticks of walking east were applied")
	var feeling: int = log.filter(func(a: Applied) -> bool: return a.holds == InputRecord.HOLD_FEEL).size()
	assert_eq(feeling, 6, "feel held for six ticks")
	var chalks: Array[int] = []
	for a: Applied in log:
		for action: ActionRecord in a.actions:
			chalks.append(action.arg)
	assert_eq(chalks, [4] as Array[int], "the chalk mark applied exactly once")
	assert_eq(log[log.size() - 1].facing, 16384, "facing 90 degrees")
	var start: Vector2 = Vector2(Sample.fixture().spot("a")) + Vector2(0.5, 0.5)
	assert_state(s, func(view: Scenario.StateView) -> bool:
		var at: Vector2 = view.miner(ann)["position"]
		return absf(at.x - start.x - 1.5) < 0.01 and absf(at.y - start.y) < 0.01,
		"ten ticks east at a walk: 1.5 tiles (MNR-01)")
	assert_eq(s.state.light_at(Vector2i(3, 2)), 0.0, "no light source: dark")


func test_streams_are_captured_per_client() -> void:
	var s: Scenario = _build()
	var ann: MinerHandle = s.miners[0]
	var bob: MinerHandle = s.miners[1]
	s.step(30)
	var frames: PackedInt64Array = s.client(ann).frame_ticks()
	assert_eq(frames.size(), 29, "a frame every tick; tick 29's arrives at the next poll")
	for i: int in frames.size():
		assert_eq(frames[i], i, "frames in tick order")
	assert_gt(s.client(ann).bytes_sent(10), 0)
	assert_stream_has(ann, func(m: Dictionary) -> bool: return int(Variants.number(m["type"])) == Protocol.Msg.WELCOME,
		"Ann's stream starts with her Welcome")
	# Negative rules: no client is ever sent another miner's name or the run seed.
	var seed_bytes: PackedByteArray = PackedByteArray()
	seed_bytes.resize(8)
	seed_bytes.encode_s64(0, Sample.SEED)
	assert_stream_never(ann, func(m: Dictionary) -> bool: return _contains(m["bytes"], "bob".to_utf8_buffer()),
		"Ann never receives Bob's name")
	assert_stream_never(bob, func(m: Dictionary) -> bool: return _contains(m["bytes"], seed_bytes),
		"no stream carries the run seed")
	assert_true(s.client(ann).decoder_ready(), "NET-04's decoder reads the capture")
	var view: ReceivedView = s.client(ann).records_at(28)
	assert_not_null(view)
	var server_at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var own_at: Vector2 = view.own["position"]
	assert_lt((own_at - server_at).length(), 0.2, "Ann's own block tracks her miner")
	assert_eq(view.tiles.size(), 0, "no light anywhere: no tiles at all")
	assert_eq(view.entities.size(), 0, "and nobody seen")


func test_gates_and_the_path_follower() -> void:
	var s: Scenario = _build()
	var a: Vector2i = s.fixture.spot("a")
	var b: Vector2i = s.fixture.spot("b")
	assert_lt(s.mine.path_distance(a, b).distance, 0.0, "the shut gate blocks the way")
	assert_eq(Scenario.next_step(s.mine, a, b), a, "nowhere to go while it is shut")
	assert_true(s.set_gate(1, true))
	assert_gt(s.mine.path_distance(a, b).distance, 0.0, "open, the rooms join")
	var next: Vector2i = Scenario.next_step(s.mine, a, b)
	var step_cost: float = 1.414 if next.x != a.x and next.y != a.y else 1.0
	assert_ne(next, a)
	assert_almost_eq(step_cost + s.mine.path_distance(next, b).distance, s.mine.path_distance(a, b).distance, 0.01,
		"the follower's step lies on a shortest path through the gate")
	assert_true(s.set_gate(1, false))
	assert_lt(s.mine.path_distance(a, b).distance, 0.0)


func test_actions_and_voice_from_the_second_miner() -> void:
	var s: Scenario = _build()
	var bob: MinerHandle = s.miners[1]
	var log: Array[Applied] = _track(s, bob)
	s.step(20)
	var callouts: Array[ActionRecord] = []
	for a: Applied in log:
		callouts.append_array(a.actions)
	assert_eq(callouts.size(), 1)
	assert_eq([callouts[0].kind, callouts[0].arg, callouts[0].aim], [ActionRecord.Kind.CALLOUT, 7, 2])
	assert_eq(bob.voice_frames_sent, 4, "four band-only voice frames, no microphone")


func test_unavailable_population_fails_loudly() -> void:
	var s: Scenario = _build()
	assert_eq(s.place_creature(WorldIds.EntityKind.BESS, Vector2i(3, 3)), 0)
	assert_push_error("CRT-01")
	assert_eq(s.place_item("oil_flask", Vector2i(3, 3)), 0)
	assert_push_error("their tickets")


static func _contains(raw: Variant, needle: PackedByteArray) -> bool:
	var haystack: PackedByteArray = raw
	var hex: String = haystack.hex_encode()
	var pattern: String = needle.hex_encode()
	var at: int = hex.find(pattern)
	while at >= 0:
		if at % 2 == 0:
			return true
		at = hex.find(pattern, at + 1)
	return false
