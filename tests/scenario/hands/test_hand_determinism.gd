extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08: Hands decide from server state alone (ties by entity, the cough from their named stream),
## so two runs of the same seed and inputs give the same Hand trajectories tick for tick: the same
## per-tick position hashes, and a golden of them that holds on Windows and Linux alike (FND-04's CI
## runs both). Re-record from the digest the test prints after a deliberate change.

const HW = preload("res://tests/unit/hands/hand_world.gd")
const W = preload("res://tests/unit/sound/signal_world.gd")
const GOLDEN: String = "ff72fd0e2492f663180bddabc554cda489120f4ceef2fd35de27e7ecba58697e"


func before_all() -> void:
	assert_true(Tuning.load_server())


## A run of two humans walking and ordering two Hands; returns each tick's hash of the Hands' poses.
func _trace() -> PackedStringArray:
	var s: Scenario = make({"seed": 4911, "fixture": HW.road(60)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(10, 0), 0.0)
	var bob: MinerHandle = HW.human(s, "bob", a + Vector2i(30, 2), 180.0)
	var hands: Array[int] = [HW.hand(s, a + Vector2i(2, 0), 4, true), HW.hand(s, a + Vector2i(40, 1), 3, true)]
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 80).wait(20).move(180.0, InputRecord.Gait.RUN, 40)
	bob.at(s.run.tick).wait(30).callout("quiet", CalloutLines.TALK).wait(60).move(180.0, InputRecord.Gait.WALK, 60)
	var out: PackedStringArray = PackedStringArray()
	for t: int in 600:
		if t == 200:
			W.signal_press(s, ann, LampSignalKind.Kind.STOP)
		if t == 320:
			ann.at(s.run.tick).callout("douse", CalloutLines.TALK)
		if t == 420:
			W.signal_press(s, ann, LampSignalKind.Kind.OK)
		s.step(1)
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		for e: int in hands:
			var hand: HandController.Hand = s.run.hands.hands[e]
			var m: MovementSystem.Miner = s.run.movement.miner(hand.slot)
			b.put_double(m.state.x)
			b.put_double(m.state.y)
			b.put_u16(m.state.facing)
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(b.data_array)
		out.append(ctx.finish().hex_encode())
	return out


func test_the_same_seed_and_inputs_give_the_same_trajectories() -> void:
	var a: PackedStringArray = _trace()
	var b: PackedStringArray = _trace()
	assert_eq(a.size(), 600)
	var first_diff: int = -1
	for i: int in a.size():
		if a[i] != b[i]:
			first_diff = i
			break
	assert_eq(first_diff, -1, "identical per-tick Hand position hashes")
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("".join(a).to_utf8_buffer())
	var digest: String = ctx.finish().hex_encode()
	gut.p("hands trajectory digest %s" % digest)
	if not GOLDEN.is_empty():
		assert_eq(digest, GOLDEN, "the golden: the same trajectories on Windows and Linux")
